local M = {}

---@type integer[]
local created = {}

--- Reads a fixture file under tests/fixtures as a list of lines.
---@param name string
---@return string[]
function M.fixture(name)
  return vim.fn.readfile(("tests/fixtures/%s"):format(name))
end

--- Scratch buffer with the given lines, markdown filetype, shown in the current
--- window and parsed. Returns the buffer and a context over every row.
---@param lines string[]
---@return integer buf, preview.Context ctx
function M.buffer_with(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  created[#created + 1] = buf
  local config = require("preview.config").defaults
  local ctx = require("preview.render.context").new(buf, win, 0, #lines - 1, config)
  return buf, ctx
end

--- Wipes every buffer created by `buffer_with`.
function M.wipe()
  for _, buf in ipairs(created) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  created = {}
end

--- Collects marks for the buffer through the real query + collect path.
---@param buf integer
---@param ctx preview.Context
---@return table<integer, preview.Mark[]>
function M.marks_for(buf, ctx)
  local render = require("preview.render")
  local query = require("preview.render.query")
  local elements = render.elements()
  local marks = render.collect(ctx, elements, query.matches(buf, elements, ctx.top, ctx.bot))
  return marks
end

--- Marks on one row filtered by predicate. Pure.
---@param by_row table<integer, preview.Mark[]>
---@param row integer
---@param pred fun(mark: preview.Mark): boolean
---@return preview.Mark[]
function M.find(by_row, row, pred)
  local out = {}
  for _, mark in ipairs(by_row[row] or {}) do
    if pred(mark) then
      out[#out + 1] = mark
    end
  end
  return out
end

--- Predicate: mark conceals text (has `conceal` and an `end_col`).
---@param mark preview.Mark
---@return boolean
function M.is_conceal(mark)
  return mark.opts.conceal ~= nil and mark.opts.end_col ~= nil
end

--- Predicate builder: mark carries virtual text at the given position.
---@param pos "inline"|"overlay"|"right_align"
---@return fun(mark: preview.Mark): boolean
function M.has_virt(pos)
  return function(mark)
    return mark.opts.virt_text ~= nil and mark.opts.virt_text_pos == pos
  end
end

--- Predicate builder: mark uses the given highlight group as `hl_group`.
---@param group string
---@return fun(mark: preview.Mark): boolean
function M.has_hl(group)
  return function(mark)
    return mark.opts.hl_group == group
  end
end

--- Concatenated text of a mark's virt_text chunks. Pure.
---@param mark preview.Mark
---@return string
function M.virt_string(mark)
  local parts = {}
  for _, chunk in ipairs(mark.opts.virt_text or {}) do
    parts[#parts + 1] = chunk[1]
  end
  return table.concat(parts)
end

--- Context copy with a render config override merged over the default. Pure.
---@param ctx preview.Context
---@param override table
---@return preview.Context
function M.with_config(ctx, override)
  local copy = vim.deepcopy(ctx)
  copy.config = vim.tbl_deep_extend("force", vim.deepcopy(ctx.config), override)
  return copy
end

return M
