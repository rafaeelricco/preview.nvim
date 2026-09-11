local winbar = require("preview.ui.winbar")

local HANDLER_BUTTON = "@v:lua.require'preview.ui.winbar'.on_button_click@"

--- Plain substring test, no patterns.
---@param haystack string
---@param needle string
---@return boolean
local function has(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

describe("winbar.build", function()
  it("starts with the winbar group and right-aligns everything", function()
    local s = winbar.build("markdown")
    assert.equals("%#PreviewWinbar#%=", s:sub(1, #"%#PreviewWinbar#%="))
  end)

  it("wraps both buttons in the button click handler with minwid 1 and 2", function()
    local s = winbar.build("markdown")
    assert.is_true(has(s, "%1" .. HANDLER_BUTTON))
    assert.is_true(has(s, "%2" .. HANDLER_BUTTON))
    assert.is_true(has(s, " Preview "))
    assert.is_true(has(s, " Markdown "))
    assert.is_true(has(s, "%X"))
  end)

  it("ends after the Markdown button", function()
    local s = winbar.build("markdown")
    assert.equals(" Markdown %X", s:sub(-#" Markdown %X"))
  end)

  it("marks Markdown active and Preview inactive in markdown mode", function()
    local s = winbar.build("markdown")
    assert.is_true(has(s, "%#PreviewButtonActive# Markdown "))
    assert.is_true(has(s, "%#PreviewButtonInactive# Preview "))
  end)

  it("marks Preview active and Markdown inactive in preview mode", function()
    local s = winbar.build("preview")
    assert.is_true(has(s, "%#PreviewButtonActive# Preview "))
    assert.is_true(has(s, "%#PreviewButtonInactive# Markdown "))
  end)

  it("contains no breadcrumb items", function()
    local s = winbar.build("markdown")
    assert.is_false(has(s, "PreviewCrumb"))
    assert.is_false(has(s, "on_crumb_click"))
  end)

  it("is pure: same inputs give the same string", function()
    assert.equals(winbar.build("preview"), winbar.build("preview"))
  end)
end)

describe("winbar.EXPR", function()
  it("evaluates render() inside a %{% %} item", function()
    assert.equals("%{%v:lua.require'preview.ui.winbar'.render()%}", winbar.EXPR)
  end)
end)

describe("winbar.render", function()
  local state

  before_each(function()
    package.loaded["preview.state"] = nil
    state = require("preview.state")
    state.reset()
    winbar.configure({ enabled = true })
  end)

  after_each(function()
    state.reset()
  end)

  it("returns an empty string for an unmanaged window", function()
    assert.equals("", winbar.render())
  end)

  it("renders the buttons with the window's mode active", function()
    local win = vim.api.nvim_get_current_win()
    state.set_window(win, { buf = vim.api.nvim_get_current_buf(), mode = "preview", saved_options = {}, saved_winbar = "", saved_bar_mappings = {}, bar_managed = false })
    local s = winbar.render()
    assert.is_true(has(s, "%#PreviewButtonActive# Preview "))
    assert.is_true(has(s, "%1" .. HANDLER_BUTTON))
  end)
end)

describe("winbar click handlers", function()
  local calls
  local original_preview
  local original_getmousepos

  before_each(function()
    calls = {}
    original_preview = package.loaded["preview"]
    original_getmousepos = vim.fn.getmousepos
    package.loaded["preview"] = {
      set_mode = function(win, mode)
        calls[#calls + 1] = { win = win, mode = mode }
      end,
    }
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return { winid = 0 }
    end
  end)

  after_each(function()
    package.loaded["preview"] = original_preview
    vim.fn.getmousepos = original_getmousepos
  end)

  it("maps minwid 1 to preview on the current window when the mouse has no window", function()
    winbar.on_button_click(1, 1, "l", "")
    assert.are.same({ { win = vim.api.nvim_get_current_win(), mode = "preview" } }, calls)
  end)

  it("maps minwid 2 to markdown", function()
    winbar.on_button_click(2, 1, "l", "")
    assert.equals("markdown", calls[1].mode)
  end)

  it("uses the window under the mouse when known", function()
    vim.cmd.vsplit()
    local other = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return { winid = other }
    end
    winbar.on_button_click(1, 1, "l", "")
    assert.equals(other, calls[1].win)
    vim.api.nvim_win_close(other, true)
  end)

  it("ignores an unknown minwid", function()
    winbar.on_button_click(9, 1, "l", "")
    assert.are.same({}, calls)
  end)
end)
