local layout = require("preview.render.layout")

local MIN_WIDTH = 3
local BORDER = "PreviewTable"
local BODY = "PreviewTableBody"
local HEADER = "PreviewTableHeader"

---@type table<string, "header"|"delimiter"|"body">
local KINDS = {
  pipe_table_header = "header",
  pipe_table_delimiter_row = "delimiter",
  pipe_table_row = "body",
}

---@class preview.TableCell
---@field start_col integer
---@field end_col integer
---@field width integer
---@field text string

---@class preview.TableRow
---@field row integer
---@field start_col integer
---@field end_col integer
---@field kind "header"|"delimiter"|"body"
---@field cells preview.TableCell[]

---@param marks preview.Mark[]
---@param row integer
---@param start_col integer
---@param end_col integer
local function conceal(marks, row, start_col, end_col)
  if start_col >= end_col then return end
  marks[#marks + 1] = {
    row = row,
    col = start_col,
    opts = { end_col = end_col, conceal = "" },
  }
end

---@param marks preview.Mark[]
---@param row integer
---@param col integer
---@param text string
local function inline(marks, row, col, text)
  if text == "" then return end
  marks[#marks + 1] = {
    row = row,
    col = col,
    opts = { virt_text = { { text, BORDER } }, virt_text_pos = "inline" },
  }
end

---@param marks preview.Mark[]
---@param row integer
---@param start_col integer
---@param end_col integer
---@param hl string
local function highlight(marks, row, start_col, end_col, hl)
  if start_col >= end_col then return end
  marks[#marks + 1] = {
    row = row,
    col = start_col,
    opts = { end_col = end_col, hl_group = hl, priority = 150 },
  }
end

---@param text string
---@return integer, integer
local function trim_offsets(text)
  local leading = #(text:match("^%s*") or "")
  local trailing = #(text:match("%s*$") or "")
  if leading + trailing > #text then trailing = #text - leading end
  return leading, trailing
end

--- Read cell byte ranges between the grammar's direct unnamed pipe children,
--- so empty cells remain addressable and escaped pipes stay inside a cell.
---@param node TSNode
---@param ctx preview.Context
---@param kind "header"|"delimiter"|"body"
---@param prior_marks table<integer, preview.Mark[]>
---@return preview.TableRow
local function read_row(node, ctx, kind, prior_marks)
  local row, start_col, _, end_col = node:range()
  ---@type preview.TableRow
  local result = {
    row = row,
    start_col = start_col,
    end_col = end_col,
    kind = kind,
    cells = {},
  }
  if kind == "delimiter" then return result end

  ---@type { start_col: integer, end_col: integer }[]
  local pipes = {}
  for child in node:iter_children() do
    if not child:named() and child:type() == "|" then
      local _, pipe_start, _, pipe_end = child:range()
      pipes[#pipes + 1] = { start_col = pipe_start, end_col = pipe_end }
    end
  end

  local first_pipe = pipes[1]
  local last_pipe = pipes[#pipes]
  local has_leading = first_pipe and first_pipe.start_col == start_col
  local has_trailing = last_pipe and last_pipe.end_col == end_col
  local cursor = has_leading and first_pipe.end_col or start_col
  local first_internal = has_leading and 2 or 1
  local last_internal = #pipes - (has_trailing and 1 or 0)

  ---@param raw_start integer
  ---@param raw_end integer
  local function add_cell(raw_start, raw_end)
    local raw = ctx.lines(row):sub(raw_start + 1, raw_end)
    local leading, trailing = trim_offsets(raw)
    local cell_start = raw_start + leading
    local cell_end = raw_end - trailing
    local width, text = layout.measure(
      ctx, row, cell_start, cell_end, prior_marks[row] or {})
    result.cells[#result.cells + 1] = {
      start_col = cell_start,
      end_col = cell_end,
      width = width,
      text = text,
    }
  end

  for index = first_internal, last_internal do
    add_cell(cursor, pipes[index].start_col)
    cursor = pipes[index].end_col
  end
  add_cell(cursor, has_trailing and last_pipe.start_col or end_col)
  return result
end

---@param root TSNode
---@param ctx preview.Context
---@param prior_marks table<integer, preview.Mark[]>
---@return preview.TableRow[]
local function read_rows(root, ctx, prior_marks)
  ---@type preview.TableRow[]
  local rows = {}
  for node in root:iter_children() do
    local kind = KINDS[node:type()]
    if kind then rows[#rows + 1] = read_row(node, ctx, kind, prior_marks) end
  end
  return rows
end

---@param rows preview.TableRow[]
---@return integer[], integer
local function natural_widths(rows)
  local columns = 0
  for _, row in ipairs(rows) do
    if row.kind ~= "delimiter" then columns = math.max(columns, #row.cells) end
  end
  ---@type integer[]
  local widths = {}
  for index = 1, columns do widths[index] = MIN_WIDTH end
  for _, row in ipairs(rows) do
    if row.kind ~= "delimiter" then
      for index, cell in ipairs(row.cells) do
        widths[index] = math.max(widths[index], cell.width)
      end
    end
  end
  local total = columns + 1
  for _, width in ipairs(widths) do total = total + width + 2 end
  return widths, total
end

---@param widths integer[]
---@param left string
---@param middle string
---@param right string
---@return string
local function rule(widths, left, middle, right)
  local parts = { left }
  for index, width in ipairs(widths) do
    parts[#parts + 1] = ("─"):rep(width + 2)
    parts[#parts + 1] = index == #widths and right or middle
  end
  return table.concat(parts)
end

--- Neovim wraps by source width plus inline text, ignoring conceal, so a
--- padded run keeps its own source spaces: only a shortfall becomes inline
--- text and only an excess is hidden.
---@param marks preview.Mark[]
---@param line string
---@param row integer
---@param start_col integer
---@param end_col integer
---@param wanted integer
local function pad(marks, line, row, start_col, end_col, wanted)
  local spaces = line:sub(start_col + 1, end_col):match("^ *$") and end_col - start_col or 0
  local kept = math.min(spaces, wanted)
  inline(marks, row, start_col, (" "):rep(wanted - kept))
  conceal(marks, row, start_col + kept, end_col)
end

--- Draws the source around one cell boundary, whitespace and at most one
--- pipe, as `before` spaces, a border and `after` spaces.
---@param marks preview.Mark[]
---@param line string
---@param row integer
---@param start_col integer
---@param end_col integer
---@param before integer
---@param after integer
local function separator(marks, line, row, start_col, end_col, before, after)
  local offset = line:sub(start_col + 1, end_col):find("|", 1, true)
  if not offset then
    pad(marks, line, row, start_col, end_col, before)
    inline(marks, row, end_col, "│" .. (" "):rep(after))
    return
  end
  local pipe = start_col + offset - 1
  pad(marks, line, row, start_col, pipe, before)
  marks[#marks + 1] = {
    row = row,
    col = pipe,
    opts = { end_col = pipe + 1, conceal = "│", hl_group = BORDER },
  }
  pad(marks, line, row, pipe + 1, end_col, after)
end

---@param row preview.TableRow
---@param widths integer[]
---@param marks preview.Mark[]
---@param line string
local function decorate_grid_row(row, widths, marks, line)
  local cells = row.cells
  if #cells == 0 then return end
  separator(marks, line, row.row, row.start_col, cells[1].start_col, 0, 1)

  local hl = row.kind == "header" and HEADER or BODY
  for index, cell in ipairs(cells) do
    highlight(marks, row.row, cell.start_col, cell.end_col, hl)
    local next_cell = cells[index + 1]
    local before = math.max(widths[index] - cell.width, 0) + 1
    if next_cell then
      separator(marks, line, row.row, cell.end_col, next_cell.start_col, before, 1)
    else
      separator(marks, line, row.row, cell.end_col, row.end_col, before, 0)
      local missing = {}
      for column = index + 1, #widths do
        missing[#missing + 1] = (" "):rep(widths[column] + 2) .. "│"
      end
      inline(marks, row.row, row.end_col, table.concat(missing))
    end
  end
end

---@param rows preview.TableRow[]
---@return string[]
local function header_labels(rows)
  local labels = {}
  for _, row in ipairs(rows) do
    if row.kind == "header" then
      for index, cell in ipairs(row.cells) do
        labels[index] = cell.text ~= "" and cell.text or ("Column %d"):format(index)
      end
      break
    end
  end
  return labels
end

---@param row preview.TableRow
---@param marks preview.Mark[]
local function conceal_structure(row, marks)
  if #row.cells == 0 then
    conceal(marks, row.row, row.start_col, row.end_col)
    return
  end
  conceal(marks, row.row, row.start_col, row.cells[1].start_col)
  for index, cell in ipairs(row.cells) do
    local next_cell = row.cells[index + 1]
    conceal(marks, row.row, cell.end_col,
      next_cell and next_cell.start_col or row.end_col)
  end
end

---@param rows preview.TableRow[]
---@param marks preview.Mark[]
---@return preview.RowFlow[]
local function decorate_stack(rows, marks)
  local labels = header_labels(rows)
  ---@type preview.RowFlow[]
  local flows = {}
  for _, row in ipairs(rows) do
    conceal_structure(row, marks)
    ---@type preview.Field[]
    local fields = {}
    local hl = row.kind == "header" and HEADER or BODY
    if row.kind ~= "delimiter" then
      for index, cell in ipairs(row.cells) do
        highlight(marks, row.row, cell.start_col, cell.end_col, hl)
        fields[#fields + 1] = {
          start_col = cell.start_col,
          end_col = cell.end_col,
          label = row.kind == "body" and (labels[index] or ("Column %d"):format(index)) or nil,
        }
      end
    end
    flows[#flows + 1] = {
      row = row.row,
      kind = "table",
      start_col = row.start_col,
      fields = fields,
    }
  end
  return flows
end

---@param row preview.TableRow
---@param prior_marks table<integer, preview.Mark[]>
---@param ctx preview.Context
---@return string
local function rule_prefix(row, prior_marks, ctx)
  local width = layout.measure(ctx, row.row, 0, row.start_col, prior_marks[row.row] or {})
  return (" "):rep(width)
end

---@param marks preview.Mark[]
---@param row integer
---@param line preview.Chunk[]
---@param above? boolean
local function virtual_rule(marks, row, line, above)
  marks[#marks + 1] = {
    row = row,
    col = 0,
    opts = { virt_lines = { line }, virt_lines_above = above or nil },
  }
end

---@type preview.Element
return {
  name = "table",
  lang = "markdown",
  query = [[ (pipe_table) @root ]],
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@param prior_marks? table<integer, preview.Mark[]>
  ---@return preview.Mark[], preview.RowFlow[]
  render = function(ctx, m, prior_marks)
    prior_marks = prior_marks or {}
    local rows = read_rows(m.root, ctx, prior_marks)
    if #rows < 2 then return {}, {} end
    local widths, natural_width = natural_widths(rows)
    if #widths == 0 then return {}, {} end

    local container_width = layout.measure(ctx, rows[1].row, 0, rows[1].start_col, prior_marks[rows[1].row] or {})
    if ctx.view.wrap and natural_width + container_width > ctx.width then
      local marks = {}
      local flows = decorate_stack(rows, marks)
      return marks, flows
    end

    ---@type preview.Mark[]
    local marks = {}
    ---@type preview.RowFlow[]
    local flows = {}
    local middle = rule(widths, "├", "┼", "┤")
    local first, last = rows[1], rows[#rows]

    for _, row in ipairs(rows) do
      flows[#flows + 1] = { row = row.row, kind = "table", start_col = row.start_col }
      if row.kind == "delimiter" then
        conceal(marks, row.row, row.start_col, row.end_col)
        -- An overlay adds no native wrap width; unwrapped lines keep the rule
        -- inline so it scrolls with the text.
        marks[#marks + 1] = {
          row = row.row,
          col = row.start_col,
          opts = { virt_text = { { middle, BORDER } }, virt_text_pos = ctx.view.wrap and "overlay" or "inline" },
        }
      else
        decorate_grid_row(row, widths, marks, ctx.lines(row.row))
      end
    end

    if ctx.config.table.border then
      virtual_rule(marks, first.row, {
        { rule_prefix(first, prior_marks, ctx) .. rule(widths, "┌", "┬", "┐"), BORDER },
      }, true)
      virtual_rule(marks, last.row, {
        { rule_prefix(last, prior_marks, ctx) .. rule(widths, "└", "┴", "┘"), BORDER },
      })
    end

    if ctx.config.table.row_lines then
      for index, row in ipairs(rows) do
        if row.kind == "body" then
          local later_body = false
          for next_index = index + 1, #rows do
            if rows[next_index].kind == "body" then later_body = true break end
          end
          if later_body then
            virtual_rule(marks, row.row, {
              { rule_prefix(row, prior_marks, ctx) .. middle, BORDER },
            })
          end
        end
      end
    end
    return marks, flows
  end,
}
