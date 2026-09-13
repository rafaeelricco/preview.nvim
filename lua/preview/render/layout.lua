local M = {}

-- Neovim's character slicing keeps combining sequences with their base.
local function character(text, col)
  local value = vim.fn.strcharpart(text:sub(col + 1), 0, 1, true)
  return value ~= "" and value or nil
end
local NORMAL = "Normal"

---@param text string
---@param hl? string
---@return preview.Chunk
local function chunk(text, hl)
  return { text, hl or NORMAL }
end

---@param chunks preview.Chunk[]
---@return string
local function chunk_text(chunks)
  local out = {}
  for _, item in ipairs(chunks or {}) do out[#out + 1] = item[1] end
  return table.concat(out)
end

---@param ctx preview.Context
---@param text string
---@param col integer
---@return integer
local function text_width(ctx, text, col)
  local width = 0
  local stops = {}
  for value in (ctx.vartabstop or ""):gmatch("%d+") do
    local stop = tonumber(value)
    if stop and stop > 0 then stops[#stops + 1] = stop end
  end

  local function tab_width(at)
    if #stops == 0 then
      local stop = math.max(ctx.tabstop or 8, 1)
      return stop - (at % stop)
    end
    local boundary = 0
    for _, stop in ipairs(stops) do
      boundary = boundary + stop
      if at < boundary then return boundary - at end
    end
    local stop = stops[#stops]
    return stop - ((at - boundary) % stop)
  end

  for index = 0, vim.fn.strchars(text, true) - 1 do
    local char = vim.fn.strcharpart(text, index, 1, true)
    if char == "\t" then
      width = width + tab_width(col + width)
    else
      width = width + vim.fn.strdisplaywidth(char)
    end
  end
  return width
end

---@param window_width integer
---@param view preview.View
---@return integer width, integer left
function M.geometry(window_width, view)
  local total = math.max(window_width, 1)
  local gutter = math.min(math.max(view.gutter or 0, 0), total - 1)
  if not view.wrap then
    return math.max(total - gutter, 1), gutter
  end
  gutter = math.min(gutter, math.floor((total - 1) / 2))
  local available = math.max(total - 2 * gutter, 1)
  local width = view.max_width == 0 and available or math.min(view.max_width, available)
  width = math.max(width, 1)
  local left = view.center and math.floor((total - width) / 2) or math.min(gutter, total - width)
  return width, math.max(left, 0)
end

---@class preview.LayoutAtom
---@field text string
---@field start_col integer
---@field end_col integer

---@param ctx preview.Context
---@param row integer
---@param start_col integer
---@param end_col integer
---@param marks preview.Mark[]
---@return preview.LayoutAtom[]
local function visible_atoms(ctx, row, start_col, end_col, marks)
  local line = ctx.lines(row)
  start_col = math.max(math.min(start_col, #line), 0)
  end_col = math.max(math.min(end_col, #line), start_col)

  ---@type table<integer, preview.Chunk[]>
  local inline = {}
  ---@type { start_col: integer, end_col: integer, replacement: string }[]
  local ranges = {}
  for _, mark in ipairs(marks or {}) do
    local opts = mark.opts or {}
    if opts.virt_text and opts.virt_text_pos == "inline" and mark.col >= start_col and mark.col < end_col then
      inline[mark.col] = inline[mark.col] or {}
      vim.list_extend(inline[mark.col], opts.virt_text)
    end
    if opts.conceal ~= nil and (opts.end_col or mark.col) > start_col and mark.col < end_col then
      ranges[#ranges + 1] = {
        start_col = math.max(mark.col, start_col),
        end_col = math.min(opts.end_col or mark.col, end_col),
        replacement = opts.conceal,
      }
    end
  end
  table.sort(ranges, function(a, b)
    if a.start_col ~= b.start_col then return a.start_col < b.start_col end
    return a.end_col > b.end_col
  end)

  --- Conceal ranges form a union. A replacement belongs to that visible run,
  --- rather than to every overlapping extmark in it.
  ---@type { start_col: integer, end_col: integer, replacement: string }[]
  local concealed = {}
  for _, range in ipairs(ranges) do
    local last = concealed[#concealed]
    if last and range.start_col < last.end_col then
      last.end_col = math.max(last.end_col, range.end_col)
      if last.replacement == "" and range.replacement ~= "" then
        last.replacement = range.replacement
      end
    else
      concealed[#concealed + 1] = vim.deepcopy(range)
    end
  end

  ---@type preview.LayoutAtom[]
  local atoms = {}
  local function add(text, first, last)
    if text ~= "" then atoms[#atoms + 1] = { text = text, start_col = first, end_col = last } end
  end

  local col, range_index = start_col, 1
  while col < end_col do
    for _, item in ipairs(inline[col] or {}) do add(item[1], col, col) end
    local range = concealed[range_index]
    if range and col == range.start_col then
      add(range.replacement, col, range.end_col)
      col = range.end_col
      range_index = range_index + 1
    else
      local char = character(line, col)
      if not char then break end
      add(char, col, col + #char)
      col = col + #char
    end
  end
  return atoms
end

---@param ctx preview.Context
---@param row integer
---@param start_col integer
---@param end_col integer
---@param marks preview.Mark[]
---@return integer, string
function M.measure(ctx, row, start_col, end_col, marks)
  local atoms = visible_atoms(ctx, row, start_col, end_col, marks)
  local parts, width = {}, 0
  for _, atom in ipairs(atoms) do
    parts[#parts + 1] = atom.text
    width = width + text_width(ctx, atom.text, width)
  end
  return width, table.concat(parts)
end

---@param additions table<integer, preview.Chunk[]>
---@param col integer
---@param chunks preview.Chunk[]
local function add_inline(additions, col, chunks)
  if #chunks == 0 then return end
  additions[col] = additions[col] or {}
  vim.list_extend(additions[col], chunks)
end

---@param marks preview.Mark[]
---@return table<integer, preview.Chunk[]>
local function native_mark_events(marks)
  local events = {}
  for _, mark in ipairs(marks) do
    local opts = mark.opts or {}
    if opts.virt_text and opts.virt_text_pos == "inline" then
      events[mark.col] = events[mark.col] or {}
      vim.list_extend(events[mark.col], opts.virt_text)
    end
  end
  return events
end

---@param ctx preview.Context
---@param absolute integer
---@param marks? preview.Chunk[]
---@param additions? preview.Chunk[]
---@return integer
local function native_event_width(ctx, absolute, marks, additions)
  -- Layout additions precede element icons at a shared source column.
  for _, item in ipairs(additions or {}) do
    absolute = absolute + text_width(ctx, item[1], absolute)
  end
  for _, item in ipairs(marks or {}) do
    absolute = absolute + text_width(ctx, item[1], absolute)
  end
  return absolute
end

---@param ctx preview.Context
---@param line string
---@param col integer
---@param absolute integer
---@param mark_events table<integer, preview.Chunk[]>
---@param additions table<integer, preview.Chunk[]>
---@return integer next_col, integer next_absolute
local function native_advance(ctx, line, col, absolute, mark_events, additions)
  absolute = native_event_width(ctx, absolute, mark_events[col], additions[col])
  local char = character(line, col)
  if not char then return col, absolute end
  return col + #char, absolute + text_width(ctx, char, absolute)
end

---@param ctx preview.Context
---@param line string
---@param marks preview.Mark[]
---@param additions table<integer, preview.Chunk[]>
---@param target integer
---@return integer column, integer row, integer absolute
local function native_column(ctx, line, marks, additions, target)
  local events = native_mark_events(marks)
  local width, col = 0, 0
  while col < target do
    local next_col
    next_col, width = native_advance(ctx, line, col, width, events, additions)
    if next_col == col then break end
    col = next_col
  end
  return width % ctx.window_width, math.floor(width / ctx.window_width), width
end

---@param ctx preview.Context
---@param row integer
---@param marks preview.Mark[]
---@param additions table<integer, preview.Chunk[]>
---@param col integer
---@param prefix preview.Chunk[]
---@param fill_hl? string
---@param current? integer
local function force_break(ctx, row, marks, additions, col, prefix, fill_hl, current)
  current = current or native_column(ctx, ctx.lines(row), marks, additions, col)
  local fill = current == 0 and 0 or ctx.window_width - current
  local chunks = {}
  if fill > 0 then
    local shaded = fill_hl and math.min(fill, math.max(ctx.left + ctx.width - current, 0)) or 0
    if shaded > 0 then chunks[#chunks + 1] = chunk((" "):rep(shaded), fill_hl) end
    if fill > shaded then chunks[#chunks + 1] = chunk((" "):rep(fill - shaded)) end
  end
  vim.list_extend(chunks, prefix)
  add_inline(additions, col, chunks)
end

---@param ctx preview.Context
---@param additions table<integer, preview.Chunk[]>
---@param mark_events table<integer, preview.Chunk[]>
---@param target integer
---@param absolute integer
---@return integer
local function native_after_events(ctx, additions, mark_events, target, absolute)
  return native_event_width(ctx, absolute, mark_events[target], additions[target])
end

---@param ctx preview.Context
---@param row integer
---@param marks preview.Mark[]
---@param additions table<integer, preview.Chunk[]>
---@param start_col integer
---@param end_col integer
---@param first_width integer
---@param continuation_width integer
---@param prefix preview.Chunk[]
---@param fill_hl? string
---@return integer[]
local function wrap_row(ctx, row, marks, additions, start_col, end_col,
    first_width, continuation_width, prefix, fill_hl)
  local line = ctx.lines(row)
  local atoms = visible_atoms(ctx, row, start_col, end_col, marks)
  first_width = math.max(first_width, 1)
  continuation_width = math.max(continuation_width, 1)
  prefix = prefix or {}
  local mark_events = native_mark_events(marks)

  -- Native positions are source byte boundaries before events at that byte.
  -- A new layout addition only invalidates positions after its insertion point.
  local positions = { [0] = 0 }
  local scan_col, scan_absolute, valid_until = 0, 0, 0
  local function native_absolute(target)
    if target <= valid_until then return positions[target] end
    while scan_col < target do
      local next_col
      next_col, scan_absolute = native_advance(
        ctx, line, scan_col, scan_absolute, mark_events, additions)
      if next_col == scan_col then break end
      scan_col = next_col
      positions[scan_col] = scan_absolute
    end
    valid_until = scan_col
    return positions[target] or scan_absolute
  end

  local function rewind(point, absolute)
    scan_col, scan_absolute, valid_until = point, absolute, point
  end

  --- Keep words intact when both the rendered text and its native source fit.
  --- Atoms remain character-grained for hard breaks in an oversized word.
  local runs = {}
  for _, atom in ipairs(atoms) do
    local whitespace = atom.text:match("^%s+$") ~= nil
    local last = runs[#runs]
    if last and last.whitespace == whitespace then
      last.atoms[#last.atoms + 1] = atom
      last.parts[#last.parts + 1] = atom.text
      last.end_col = atom.end_col
    else
      runs[#runs + 1] = {
        atoms = { atom }, parts = { atom.text }, whitespace = whitespace,
        start_col = atom.start_col, end_col = atom.end_col,
      }
    end
  end
  for _, run in ipairs(runs) do run.text = table.concat(run.parts) end

  local points = {}
  local used, capacity = 0, first_width
  local pending_width, pending_end = 0, nil
  local start_absolute = native_absolute(start_col)
  start_absolute = native_after_events(ctx, additions, mark_events, start_col, start_absolute)
  local native_row = math.floor(start_absolute / ctx.window_width)

  local function add_break(point)
    if point <= (points[#points] or -1) then return false end
    local absolute = native_absolute(point)
    force_break(ctx, row, marks, additions, point, prefix, fill_hl, absolute % ctx.window_width)
    points[#points + 1] = point
    used, pending_width, pending_end = 0, 0, nil
    capacity = continuation_width
    rewind(point, absolute)
    local after = native_after_events(ctx, additions, mark_events, point, absolute)
    native_row = math.floor(after / ctx.window_width)
    return true
  end

  local function native_fits(first, last)
    local first_absolute = native_absolute(first)
    first_absolute = native_after_events(ctx, additions, mark_events, first, first_absolute)
    local first_row = math.floor(first_absolute / ctx.window_width)
    local last_absolute = native_absolute(last)
    if first == last then
      last_absolute = first_absolute
    end
    return first_row == native_row and last_absolute <= (native_row + 1) * ctx.window_width
  end

  for _, run in ipairs(runs) do
    if run.whitespace then
      pending_width = pending_width + text_width(ctx, run.text, used + pending_width)
      pending_end = run.end_col
    else
      local width = text_width(ctx, run.text, used + pending_width)
      local visible_fits = used + pending_width + width <= capacity
      local source_fits = native_fits(run.start_col, run.end_col)
      if (not visible_fits or not source_fits) and used > 0 then
        local point = pending_end or run.start_col
        add_break(point)
        -- A concealed span can cross more native rows after the whitespace at
        -- the chosen word boundary. Realign once more where text resumes.
        if not native_fits(run.start_col, run.end_col) and point < run.start_col then
          add_break(run.start_col)
        end
        width = text_width(ctx, run.text, 0)
        visible_fits = width <= capacity
        source_fits = native_fits(run.start_col, run.end_col)
      else
        used = used + pending_width
        pending_width, pending_end = 0, nil
      end

      if visible_fits and source_fits then
        used = used + width
      else
        for _, atom in ipairs(run.atoms) do
          local atom_width = text_width(ctx, atom.text, used)
          local atom_fits = native_fits(atom.start_col, atom.end_col)
          if atom_width > 0 and used > 0 and (used + atom_width > capacity or not atom_fits) then
            add_break(atom.start_col)
            atom_width = text_width(ctx, atom.text, 0)
            atom_fits = native_fits(atom.start_col, atom.end_col)
          elseif not atom_fits and used == 0 then
            add_break(atom.start_col)
            atom_fits = native_fits(atom.start_col, atom.end_col)
          end
          used = used + atom_width
          -- If raw bytes inside this atom consumed another native row, keep
          -- the visible row here; the next atom will be explicitly realigned.
          if atom_fits then
            local absolute = native_absolute(atom.end_col)
            native_row = math.floor(absolute / ctx.window_width)
          end
        end
      end
    end
  end
  return points
end

---@param marks preview.Mark[]
---@param additions table<integer, preview.Chunk[]>
---@param row integer
---@return preview.Mark[]
local function merge_inline(marks, additions, row)
  local first = {}
  local colocated = {}
  local remove = {}
  for index, mark in ipairs(marks) do
    colocated[mark.col] = colocated[mark.col] or index
    local opts = mark.opts or {}
    if opts.virt_text and opts.virt_text_pos == "inline" then
      local carrier = first[mark.col]
      if not carrier then
        first[mark.col] = index
      else
        local target = marks[carrier].opts.virt_text or {}
        vim.list_extend(target, opts.virt_text)
        mark.opts.virt_text, mark.opts.virt_text_pos = nil, nil
        if vim.tbl_isempty(mark.opts) then remove[index] = true end
      end
    end
  end
  for col, chunks in pairs(additions) do
    local index = first[col]
    if index then
      local joined = {}
      vim.list_extend(joined, chunks)
      vim.list_extend(joined, marks[index].opts.virt_text)
      marks[index].opts.virt_text = joined
    elseif colocated[col] and not marks[colocated[col]].opts.virt_text then
      index = colocated[col]
      marks[index].opts.virt_text = chunks
      marks[index].opts.virt_text_pos = "inline"
    else
      marks[#marks + 1] = { row = row, col = col, opts = { virt_text = chunks, virt_text_pos = "inline" } }
    end
  end
  if vim.tbl_isempty(remove) then return marks end
  local out = {}
  for index, mark in ipairs(marks) do if not remove[index] then out[#out + 1] = mark end end
  return out
end

--- Removes the first `cells` display cells from window-column chunks so they
--- track text a nowrap window has scrolled left. A wide character cut in half
--- becomes a space. Everything removed → one empty chunk keeps the row.
---@param ctx preview.Context
---@param chunks preview.Chunk[]
---@param cells integer
---@return preview.Chunk[]
local function drop_cells(ctx, chunks, cells)
  if cells <= 0 then return chunks end
  local out = {}
  for _, item in ipairs(chunks) do
    local text = item[1]
    if cells > 0 then
      local width = text_width(ctx, text, 0)
      if width <= cells then
        cells, text = cells - width, ""
      else
        local index = 0
        while cells > 0 do
          cells = cells - text_width(ctx, vim.fn.strcharpart(text, index, 1, true), 0)
          index = index + 1
        end
        text = vim.fn.strcharpart(text, index, vim.fn.strchars(text, true), true)
        if cells < 0 then text = (" "):rep(-cells) .. text end
      end
    end
    if text ~= "" then out[#out + 1] = { text, item[2] } end
  end
  return #out > 0 and out or { chunk("", chunks[1] and chunks[1][2]) }
end

---@param ctx preview.Context
---@param row integer
---@param marks preview.Mark[]
local function shift_non_inline(ctx, row, marks)
  for _, mark in ipairs(marks) do
    local opts = mark.opts or {}
    if opts.virt_lines then
      for _, line in ipairs(opts.virt_lines) do
        if ctx.left > 0 then table.insert(line, 1, chunk((" "):rep(ctx.left))) end
      end
      -- Neovim scrolls the line with the text under 'nowrap'; no trim needed.
      opts.virt_lines_overflow = "scroll"
    end
    if opts.virt_text and opts.virt_text_pos == "overlay" then
      local before = M.measure(ctx, row, 0, mark.col, marks)
      opts.virt_text_pos = nil
      opts.virt_text_win_col = ctx.left + before
    end
    if opts.virt_text_win_col and ctx.leftcol > 0 then
      local hidden = math.min(opts.virt_text_win_col, ctx.leftcol)
      opts.virt_text_win_col = opts.virt_text_win_col - hidden
      opts.virt_text = drop_cells(ctx, opts.virt_text, ctx.leftcol - hidden)
    end
  end
end

---@param ctx preview.Context
---@param by_row table<integer, preview.Mark[]>
---@param row_flows table<integer, preview.RowFlow>
---@return table<integer, preview.Mark[]>
function M.apply(ctx, by_row, row_flows)
  local out = vim.deepcopy(by_row or {})
  row_flows = row_flows or {}
  for row = ctx.top, ctx.bot do
    local marks = out[row] or {}
    out[row] = marks
    local flow = row_flows[row]
    local additions = {}
    local left = ctx.left > 0 and { chunk((" "):rep(ctx.left)) } or {}

    if flow and flow.kind == "table" and flow.fields and #flow.fields > 0 then
      local container_width, container_text = M.measure(ctx, row, 0, flow.start_col or 0, marks)
      local available = math.max(ctx.width - container_width, 1)
      local function base()
        local chunks = vim.deepcopy(left)
        if container_text ~= "" then chunks[#chunks + 1] = chunk(container_text, "PreviewQuote") end
        return chunks
      end
      add_inline(additions, 0, left)
      for index, field in ipairs(flow.fields) do
        local label = field.label and (field.label .. ": ") or ""
        local label_width = 0
        local label_offset = index == 1 and (native_column(ctx, ctx.lines(row), marks, additions, field.start_col) - ctx.left - container_width) or 0
        local prefix = index == 1 and {} or base()
        -- Labels are virtual, but still obey the column in very narrow views.
        for char_index = 0, vim.fn.strchars(label, true) - 1 do
          local char = vim.fn.strcharpart(label, char_index, 1, true)
          local size = text_width(ctx, char, label_width)
          if label_width > 0 and label_width + size > available then
            prefix[#prefix + 1] = chunk((" "):rep(math.max(ctx.window_width - ctx.left - container_width - label_width - label_offset, 0)))
            vim.list_extend(prefix, base())
            label_width, label_offset = 0, 0
          end
          prefix[#prefix + 1] = chunk(char, "PreviewTableHeader")
          label_width = label_width + size
        end
        if label_width >= available then
          prefix[#prefix + 1] = chunk((" "):rep(math.max(ctx.window_width - ctx.left - container_width - label_width - label_offset, 0)))
          vim.list_extend(prefix, base())
          label_width = 0
        end
        if index == 1 then
          add_inline(additions, field.start_col, prefix)
        else
          force_break(ctx, row, marks, additions, field.start_col, prefix)
        end
        if ctx.view.wrap then
          local continuation = base()
          continuation[#continuation + 1] = chunk((" "):rep(label_width))
          wrap_row(ctx, row, marks, additions, field.start_col, field.end_col,
            available - label_width, available - label_width, continuation)
        end
      end
    else
      add_inline(additions, 0, left)
      if flow and flow.kind == "code" then
        local start_col = flow.start_col or 0
        local prefix_width, prefix_text = M.measure(ctx, row, 0, start_col, marks)
        local available = math.max(ctx.width - prefix_width, 1)
        local padding = math.min(flow.padding or 0, math.floor(math.max(available - 1, 0) / 2))
        local background = flow.background or "PreviewCodeBlock"
        if padding > 0 then add_inline(additions, start_col, { chunk((" "):rep(padding), background) }) end

        local label = flow.label and (" " .. flow.label .. " ") or nil
        if label and flow.label_position == "left" then
          add_inline(additions, start_col, { chunk(label, "PreviewCodeLabel") })
        elseif label and flow.label_position == "right" then
          local label_width = text_width(ctx, label, 0)
          marks[#marks + 1] = {
            row = row, col = start_col,
            opts = {
              virt_text = { chunk(label, "PreviewCodeLabel") },
              virt_text_win_col = ctx.left + prefix_width + math.max(available - padding - label_width, 0),
            },
          }
        end

        local content_width = math.max(available - 2 * padding, 1)
        local continuation = {}
        vim.list_extend(continuation, left)
        if prefix_width > 0 then continuation[#continuation + 1] = chunk(prefix_text, "PreviewQuote") end
        if padding > 0 then continuation[#continuation + 1] = chunk((" "):rep(padding), background) end
        local points = ctx.view.wrap and wrap_row(ctx, row, marks, additions, start_col, #ctx.lines(row),
          content_width, content_width, continuation, background) or {}

        local final_start = points[#points] or start_col
        local final_width = M.measure(ctx, row, final_start, #ctx.lines(row), marks)
        -- A fence row draws no text, but native wrapping still counts its
        -- concealed source, so the inline fill has to leave room for those cells.
        local hidden = flow.fence and (flow.source_width or 0) or 0
        local trailing = math.max(available - padding - final_width - hidden, 0)
        if trailing > 0 then add_inline(additions, #ctx.lines(row), { chunk((" "):rep(trailing), background) }) end
        -- Those reserved cells would leave the panel short by exactly the width
        -- of the hidden fence text. Window-column text costs no native columns,
        -- so it covers them without pushing the row into a wrap.
        if hidden > 0 then
          local edge = math.max(available - hidden, 0)
          marks[#marks + 1] = {
            row = row, col = start_col,
            opts = {
              virt_text = { chunk((" "):rep(hidden), background) },
              virt_text_win_col = ctx.left + prefix_width + edge,
            },
          }
        end
      elseif ctx.view.wrap then
        local container = ctx.lines(row):match("^([ >]+)") or ""
        local quote_prefix = container:find(">", 1, true) and container or ""
        local indent = flow and flow.kind == "list" and (flow.indent or 0) or #quote_prefix
        indent = math.min(indent, ctx.width - 1)
        local continuation = {}
        vim.list_extend(continuation, left)
        if quote_prefix ~= "" then
          local rendered = quote_prefix:gsub(">", ctx.config.quote.bar)
          continuation[#continuation + 1] = chunk(rendered, "PreviewQuote")
          local remainder = indent - text_width(ctx, rendered, 0)
          if remainder > 0 then continuation[#continuation + 1] = chunk((" "):rep(remainder)) end
        elseif indent > 0 then continuation[#continuation + 1] = chunk((" "):rep(indent)) end
        wrap_row(ctx, row, marks, additions, 0, #ctx.lines(row),
          ctx.width, ctx.width - indent, continuation)
      end
    end

    shift_non_inline(ctx, row, marks)
    out[row] = merge_inline(marks, additions, row)
  end
  return out
end

return M
