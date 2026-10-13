local layout = require("preview.render.layout")
local blocks = require("preview.render.blocks")

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

---@param hl string|string[]
---@return string
local function highlight_key(hl)
  if type(hl) == "table" then return table.concat(hl, "\0") end
  return hl
end

---@param chunks preview.Chunk[]
---@param text string
---@param hl string|string[]
local function append_chunk(chunks, text, hl)
  if text == "" then return end
  local previous = chunks[#chunks]
  if previous and highlight_key(previous[2]) == highlight_key(hl) then
    previous[1] = previous[1] .. text
  else
    chunks[#chunks + 1] = { text, hl }
  end
end

---@param target preview.Chunk[]
---@param source preview.Chunk[]
local function append_chunks(target, source)
  for _, chunk in ipairs(source) do append_chunk(target, chunk[1], chunk[2]) end
end

---@param ctx preview.Context
---@param chunks preview.Chunk[]
---@param width integer
---@return preview.Chunk[][]|nil
local function wrap_chunks(ctx, chunks, width)
  if width < 1 then return nil end
  ---@type { text: string, hl: string|string[], whitespace: boolean }[]
  local tokens = {}
  for _, item in ipairs(chunks) do
    for index = 0, vim.fn.strchars(item[1], true) - 1 do
      local char = vim.fn.strcharpart(item[1], index, 1, true)
      tokens[#tokens + 1] = {
        text = char,
        hl = item[2],
        whitespace = char:match("^%s+$") ~= nil,
      }
    end
  end

  ---@type preview.Chunk[][]
  local lines = { {} }
  local line_width = 0
  local function new_line()
    lines[#lines + 1] = {}
    line_width = 0
  end
  local function measure(tokens_to_measure, start)
    local used = start
    for _, token in ipairs(tokens_to_measure) do
      used = used + layout.text_width(ctx, token.text, used)
    end
    return used - start
  end
  local function append_tokens(tokens_to_append)
    for _, token in ipairs(tokens_to_append) do
      local size = layout.text_width(ctx, token.text, line_width)
      local text = token.text == "\t" and (" "):rep(size) or token.text
      append_chunk(lines[#lines], text, token.hl)
      line_width = line_width + size
    end
  end

  local index, pending = 1, {}
  while index <= #tokens do
    if tokens[index].whitespace then
      pending[#pending + 1] = tokens[index]
      index = index + 1
    else
      local word = {}
      while index <= #tokens and not tokens[index].whitespace do
        word[#word + 1] = tokens[index]
        index = index + 1
      end

      local pending_width = measure(pending, line_width)
      local word_width = measure(word, line_width + pending_width)
      if line_width > 0 and line_width + pending_width + word_width > width then
        pending = {}
        new_line()
      else
        append_tokens(pending)
        pending = {}
      end

      word_width = measure(word, line_width)
      if line_width + word_width <= width then
        append_tokens(word)
      else
        for _, token in ipairs(word) do
          local size = layout.text_width(ctx, token.text, line_width)
          if size > width then return nil end
          if line_width > 0 and line_width + size > width then
            new_line()
            size = layout.text_width(ctx, token.text, line_width)
          end
          if size > width then return nil end
          append_tokens({ token })
        end
      end
    end
  end
  if #pending > 0 and line_width + measure(pending, line_width) <= width then
    append_tokens(pending)
  end
  return lines
end

---@param rows preview.TableRow[]
---@param widths integer[]
---@param ctx preview.Context
---@param prior_marks table<integer, preview.Mark[]>
---@return preview.Chunk[][]|nil
local function grid_lines(rows, widths, ctx, prior_marks)
  ---@type preview.Chunk[][]
  local out = {}
  local function add_rule(text)
    out[#out + 1] = { { text, BORDER } }
  end
  if ctx.config.table.border then
    add_rule(rule(widths, "┌", "┬", "┐"))
  end
  local middle = rule(widths, "├", "┼", "┤")
  for row_index, row in ipairs(rows) do
    if row.kind == "delimiter" then
      add_rule(middle)
    else
      local wrapped = {}
      local height = 1
      for col, width in ipairs(widths) do
        local cell = row.cells[col]
        local chunks = cell and layout.rich_chunks(ctx, row.row, cell.start_col, cell.end_col,
          prior_marks[row.row] or {}, row.kind == "header" and HEADER or BODY) or {}
        local lines = wrap_chunks(ctx, chunks, width)
        if not lines then return nil end
        wrapped[col] = lines
        height = math.max(height, #lines)
      end
      for line_index = 1, height do
        local line = {}
        append_chunk(line, "│", BORDER)
        for col, width in ipairs(widths) do
          append_chunk(line, " ", "Normal")
          local content = wrapped[col][line_index] or {}
          append_chunks(line, content)
          local used = 0
          for _, item in ipairs(content) do
            used = used + layout.text_width(ctx, item[1], used)
          end
          append_chunk(line, (" "):rep(math.max(width - used, 0) + 1), "Normal")
          append_chunk(line, "│", BORDER)
        end
        out[#out + 1] = line
      end
      if ctx.config.table.row_lines and row.kind == "body" then
        local later_body = false
        for next_index = row_index + 1, #rows do
          if rows[next_index].kind == "body" then later_body = true break end
        end
        if later_body then add_rule(middle) end
      end
    end
  end
  if ctx.config.table.border then
    add_rule(rule(widths, "└", "┴", "┘"))
  end
  return out
end

---@param rows preview.TableRow[]
---@param ctx preview.Context
---@param prior_marks table<integer, preview.Mark[]>
---@param width integer
---@return preview.Chunk[][]|nil
local function stack_lines(rows, ctx, prior_marks, width)
  ---@type preview.Chunk[][]
  local out = {}
  local function add_rule()
    out[#out + 1] = { { ("─"):rep(width), BORDER } }
  end
  if ctx.config.table.border then add_rule() end

  local labels, header_chunks = {}, {}
  local columns = 0
  for _, row in ipairs(rows) do
    if row.kind ~= "delimiter" then columns = math.max(columns, #row.cells) end
  end
  for _, row in ipairs(rows) do
    if row.kind == "header" then
      for index, cell in ipairs(row.cells) do
        labels[index] = cell.text ~= "" and cell.text or ("Column %d"):format(index)
        header_chunks[index] = cell.text ~= ""
          and layout.rich_chunks(ctx, row.row, cell.start_col, cell.end_col, prior_marks[row.row] or {}, HEADER)
          or { { labels[index], HEADER } }
      end
      break
    end
  end
  for index = 1, columns do
    if not labels[index] then
      labels[index] = ("Column %d"):format(index)
      header_chunks[index] = { { labels[index], HEADER } }
    end
  end

  local body_rows = {}
  for _, row in ipairs(rows) do if row.kind == "body" then body_rows[#body_rows + 1] = row end end
  if #body_rows == 0 then
    for index, chunks in ipairs(header_chunks) do
      local field = {}
      append_chunks(field, chunks)
      append_chunk(field, ": ", HEADER)
      local wrapped = wrap_chunks(ctx, field, width)
      if not wrapped then return nil end
      vim.list_extend(out, wrapped)
      if ctx.config.table.row_lines and index < #header_chunks then add_rule() end
    end
  else
    for body_index, row in ipairs(body_rows) do
      for col = 1, #labels do
        local field = {}
        append_chunks(field, header_chunks[col] or { { ("Column %d"):format(col), HEADER } })
        append_chunk(field, ": ", HEADER)
        local cell = row.cells[col]
        if cell then
          append_chunks(field, layout.rich_chunks(ctx, row.row, cell.start_col, cell.end_col,
            prior_marks[row.row] or {}, BODY))
        end
        local wrapped = wrap_chunks(ctx, field, width)
        if not wrapped then return nil end
        vim.list_extend(out, wrapped)
      end
      if ctx.config.table.row_lines and body_index < #body_rows then add_rule() end
    end
  end
  if ctx.config.table.border then add_rule() end
  return out
end

---@param widths integer[]
---@param available integer
---@return integer[]|nil
local function shrink_widths(widths, available)
  local result = vim.deepcopy(widths)
  local function total()
    local value = #result + 1
    for _, width in ipairs(result) do value = value + width + 2 end
    return value
  end
  while total() > available do
    local widest, selected = MIN_WIDTH, nil
    for index, width in ipairs(result) do
      if width > widest then widest, selected = width, index end
    end
    if not selected then return nil end
    result[selected] = result[selected] - 1
  end
  return result
end

---@param block preview.Block
---@param side "above"|"below"
---@param spacing preview.SpacingConfig
---@return integer
local function block_margin(block, side, spacing)
  local value = spacing[block.kind][side]
  return type(value) == "table" and (value[block.level or 1] or 0) or value
end

---@param root TSNode
---@param rows preview.TableRow[]
---@param ctx preview.Context
---@param prior_marks table<integer, preview.Mark[]>
---@return integer|nil anchor, integer|nil trailing_gap
local function safe_anchor(root, rows, ctx, prior_marks)
  local node = root
  while true do
    local parent = node:parent()
    if not parent then break end
    local kind = parent:type()
    if kind ~= "section" and kind ~= "document" then return nil end
    node = parent
  end
  if node:type() ~= "document" then return nil end

  local all_blocks = blocks.of(node, ctx.lines)
  local table_index
  for index, block in ipairs(all_blocks) do
    if block.kind == "table" and block.srow == rows[1].row then table_index = index break end
  end
  if not table_index or table_index == 1 or table_index == #all_blocks then return nil end
  local previous, current, following = all_blocks[table_index - 1], all_blocks[table_index], all_blocks[table_index + 1]
  if not previous.anchor or not following.anchor or previous.kind == "table" or following.kind == "table" then return nil end
  if previous.kind == "list" or previous.kind == "quote" or previous.kind == "code"
    or following.kind == "list" or following.kind == "quote" or following.kind == "code" then
    return nil
  end
  if current.erow ~= rows[#rows].row or current.srow ~= rows[1].row then return nil end
  if current.srow ~= previous.erow + 2 or following.srow ~= current.erow + 2 then return nil end
  -- The leading source separator becomes the trailing rendered gap. Spaces
  -- or tabs can wrap that separator, so only empty rows have a safe height.
  if ctx.lines(previous.erow + 1) ~= "" or ctx.lines(current.erow + 1) ~= "" then
    return nil
  end

  local spacing = ctx.config.spacing
  local before = math.max(block_margin(previous, "below", spacing), block_margin(current, "above", spacing))
  local after = math.max(block_margin(current, "below", spacing), block_margin(following, "above", spacing))
  if before ~= 1 or after ~= 1 then return nil end

  local anchor = previous.erow
  local anchor_width = layout.measure(ctx, anchor, 0, #ctx.lines(anchor), prior_marks[anchor] or {})
  local preceding = root:prev_named_sibling()
  if anchor_width > ctx.width and not (preceding and preceding:type() == "paragraph") then return nil end
  return anchor, current.erow + 1
end

---@param prior_marks table<integer, preview.Mark[]>
---@param marks preview.Mark[]
---@return boolean
local function safe_virtual_spacing(prior_marks, marks)
  local concealed, virtual = {}, {}
  for row, row_marks in pairs(prior_marks) do
    for _, mark in ipairs(row_marks) do
      local opts = mark.opts or {}
      if opts.conceal_lines ~= nil then concealed[row] = true end
      if opts.virt_lines and #opts.virt_lines > 0 then virtual[row] = true end
    end
  end
  for _, mark in ipairs(marks) do
    local opts = mark.opts or {}
    if opts.conceal_lines ~= nil then concealed[mark.row] = true end
    if opts.virt_lines and #opts.virt_lines > 0 then virtual[mark.row] = true end
  end
  for row in pairs(concealed) do
    for neighbor = row - 1, row + 1 do
      if virtual[neighbor] then return false end
    end
  end
  return true
end

---@param ctx preview.Context
---@param lines preview.Chunk[][]
---@param width integer
---@return boolean
local function lines_fit(ctx, lines, width)
  for _, line in ipairs(lines) do
    local used = 0
    for _, item in ipairs(line) do
      local size = layout.text_width(ctx, item[1], used)
      if size > width - used then return false end
      used = used + size
    end
  end
  return true
end

---@param rows preview.TableRow[]
---@param raw boolean
---@return preview.RowFlow[]
local function source_flows(rows, raw)
  local flows = {}
  for _, row in ipairs(rows) do
    flows[#flows + 1] = { row = row.row, kind = "table", raw = raw or nil }
  end
  return flows
end

---@param root TSNode
---@param rows preview.TableRow[]
---@param widths integer[]
---@param available integer
---@param ctx preview.Context
---@param prior_marks table<integer, preview.Mark[]>
---@param container_width integer
---@return preview.Mark[], preview.RowFlow[]
local function render_overflow(root, rows, widths, available, ctx, prior_marks, container_width)
  local function raw()
    return {}, source_flows(rows, true)
  end
  if container_width > 0 then return raw() end

  local anchor, trailing_gap = safe_anchor(root, rows, ctx, prior_marks)
  if not anchor or not trailing_gap then return raw() end
  for row = anchor - 1, anchor + 1 do
    for _, mark in ipairs(prior_marks[row] or {}) do
      if (mark.opts or {}).virt_lines then return raw() end
      if row == anchor then
        local opts = mark.opts or {}
        if opts.virt_text or opts.conceal_lines ~= nil then return raw() end
      end
    end
  end

  local grid_widths = shrink_widths(widths, available)
  local rendered = grid_widths and grid_lines(rows, grid_widths, ctx, prior_marks)
  if rendered and not lines_fit(ctx, rendered, available) then rendered = nil end
  if not rendered then rendered = stack_lines(rows, ctx, prior_marks, available) end
  if not rendered or not lines_fit(ctx, rendered, available) then return raw() end
  ---@type preview.Chunk[][]
  local virt_lines = { { { "", "Normal" } } }
  vim.list_extend(virt_lines, rendered)
  -- Neovim cannot reliably scroll a virtual block taller than its viewport.
  -- Reserve one line for the source anchor and one for the visible trailing gap.
  if #virt_lines + 2 > ctx.window_height then return raw() end

  ---@type preview.Mark[]
  local marks = {
    { row = anchor, col = 0, opts = { virt_lines = virt_lines } },
  }
  for row = rows[1].row, rows[#rows].row do
    marks[#marks + 1] = { row = row, col = 0, opts = { conceal_lines = "" } }
  end
  marks[#marks + 1] = { row = trailing_gap, col = 0, opts = { conceal_lines = "" } }
  if not safe_virtual_spacing(prior_marks, marks) then return raw() end

  local flows = source_flows(rows, false)
  flows[#flows + 1] = { row = trailing_gap, kind = "table", replacement = true }
  for _, flow in ipairs(flows) do flow.replacement = true end
  return marks, flows
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
      return render_overflow(m.root, rows, widths, ctx.width - container_width, ctx, prior_marks, container_width)
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
    if ctx.view.wrap then
      local candidate = {}
      for _, row in ipairs(rows) do candidate[row.row] = vim.list_extend({}, prior_marks[row.row] or {}) end
      for _, mark in ipairs(marks) do table.insert(candidate[mark.row], mark) end
      for _, row in ipairs(rows) do
        if not layout.source_row_fits(ctx, row.row, candidate[row.row]) then
          return render_overflow(m.root, rows, widths, ctx.width - container_width, ctx, prior_marks, container_width)
        end
      end
    end
    return marks, flows
  end,
}
