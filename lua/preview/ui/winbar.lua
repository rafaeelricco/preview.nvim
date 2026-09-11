local M = {}

local HANDLER = "v:lua.require'preview.ui.winbar'."

--- The option value installed on managed windows.
M.EXPR = "%{%" .. HANDLER .. "render()%}"

---@type preview.WinbarConfig|nil
local config = nil

---@type preview.Mode[]  -- index = minwid
local BUTTON_MODES = { "preview", "markdown" }

--- Statusline item for one mode button. Pure.
---@param minwid integer
---@param label string
---@param active boolean
---@return string
local function button_item(minwid, label, active)
  local group = active and "%#PreviewButtonActive#" or "%#PreviewButtonInactive#"
  return "%" .. minwid .. "@" .. HANDLER .. "on_button_click@" .. group .. " " .. label .. " %X"
end

--- Pure: builds the statusline-format string, the two buttons right-aligned.
--- "%1@...on_button_click@ Preview %X" / "%2@...@ Markdown %X".
---@param mode preview.Mode
---@return string
function M.build(mode)
  return "%#PreviewWinbar#%="
    .. button_item(1, "Preview", mode == "preview")
    .. button_item(2, "Markdown", mode == "markdown")
end

--- Stores the winbar config; render() returns "" until called.
---@param cfg preview.WinbarConfig
function M.configure(cfg)
  config = cfg
end

--- Effectful entry called from the winbar option. Reads the current window
--- (the %{% %} item evaluates in the owning window) and returns "" when it is
--- not managed.
---@return string
function M.render()
  if not config then
    return ""
  end
  local mode = require("preview.state").mode(vim.api.nvim_get_current_win())
  if not mode then
    return ""
  end
  return M.build(mode)
end

--- Window under the mouse, or the current window when unknown.
---@return integer
local function clicked_window()
  local winid = vim.fn.getmousepos().winid
  if not winid or winid == 0 then
    return vim.api.nvim_get_current_win()
  end
  return winid
end

---@param minwid integer  -- 1 = preview, 2 = markdown
function M.on_button_click(minwid, _clicks, _button, _mods)
  local mode = BUTTON_MODES[minwid]
  if not mode then
    return
  end
  require("preview").set_mode(clicked_window(), mode)
end

return M
