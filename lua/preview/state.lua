local M = {}

---@type table<integer, preview.WindowState>
local windows = {}
---@type table<integer, true>
local attached = {}

---@param value any
---@return boolean
local function is_mode(value)
  return value == "preview" or value == "markdown"
end

---@param win integer
---@return preview.Mode|nil
function M.mode(win)
  local entry = windows[win]
  return entry and entry.mode or nil
end

---@param win integer
---@return preview.WindowState|nil
function M.get_window(win)
  return windows[win] and vim.deepcopy(windows[win]) or nil
end

--- Stores a copy of `entry` for `win`, replacing any previous entry.
---@param win integer
---@param entry preview.WindowState
function M.set_window(win, entry)
  vim.validate("win", win, "number")
  vim.validate("entry", entry, "table")
  vim.validate("entry.mode", entry.mode, is_mode, false, '"preview" or "markdown"')
  windows[win] = vim.deepcopy(entry)
end

---@param win integer
---@return preview.WindowState|nil  -- the removed entry
function M.drop_window(win)
  local entry = windows[win]
  windows[win] = nil
  return entry
end

--- No-op (false) when `win` is not managed or already in `mode`.
---@param win integer
---@param mode preview.Mode
---@return boolean changed
function M.set_mode(win, mode)
  vim.validate("mode", mode, is_mode, false, '"preview" or "markdown"')
  local entry = windows[win]
  if not entry or entry.mode == mode then
    return false
  end
  entry.mode = mode
  return true
end

---@param buf integer
---@return boolean
function M.is_attached(buf)
  return attached[buf] == true
end

---@param buf integer
---@param on boolean
function M.set_attached(buf, on)
  attached[buf] = on and true or nil
end

--- Windows currently showing `buf` that are in preview mode. Pure over the table plus nvim_win_get_buf.
--- Entries for windows that no longer exist are skipped. Sorted ascending.
---@param buf integer
---@return integer[]
function M.preview_windows_for(buf)
  local out = {}
  for win, entry in pairs(windows) do
    if entry.mode == "preview" and not entry.suspended and entry.buf == buf
      and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      out[#out + 1] = win
    end
  end
  table.sort(out)
  return out
end

--- Deep copy for tests.
---@return { windows: table<integer, preview.WindowState>, attached: table<integer, true> }
function M.snapshot()
  return vim.deepcopy({ windows = windows, attached = attached })
end

function M.reset()
  windows = {}
  attached = {}
end

return M
