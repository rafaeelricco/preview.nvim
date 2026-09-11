local state = require("preview.state")

---@return preview.WindowState
local function entry(mode, buf)
  return { buf = buf or vim.api.nvim_get_current_buf(), mode = mode or "markdown", saved_options = {}, saved_winbar = "", saved_bar_mappings = {}, bar_managed = false }
end

--- Opens a non-focused split showing `buf`; returns the window id.
---@param buf integer
---@return integer
local function open_window(buf)
  return vim.api.nvim_open_win(buf, false, { split = "right", win = 0 })
end

describe("preview.state", function()
  local opened

  before_each(function()
    state.reset()
    opened = {}
  end)

  after_each(function()
    for _, win in ipairs(opened) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    state.reset()
  end)

  it("round-trips set_window, mode and drop_window", function()
    local win = 1001
    assert.is_nil(state.mode(win))
    state.set_window(win, entry("markdown"))
    assert.equals("markdown", state.mode(win))
    local removed = state.drop_window(win)
    assert.are.same(entry("markdown"), removed)
    assert.is_nil(state.mode(win))
  end)

  it("drop_window returns nil for an unmanaged window", function()
    assert.is_nil(state.drop_window(4242))
  end)

  it("stores a copy of the entry", function()
    local win = 1002
    local e = entry("markdown")
    state.set_window(win, e)
    e.mode = "preview"
    assert.equals("markdown", state.mode(win))
  end)

  it("set_mode returns true only when the mode changed", function()
    local win = 1003
    state.set_window(win, entry("markdown"))
    assert.is_true(state.set_mode(win, "preview"))
    assert.equals("preview", state.mode(win))
    assert.is_false(state.set_mode(win, "preview"))
    assert.is_true(state.set_mode(win, "markdown"))
  end)

  it("set_mode returns false for an unmanaged window", function()
    assert.is_false(state.set_mode(9999, "preview"))
    assert.is_nil(state.mode(9999))
  end)

  it("tracks attached buffers", function()
    assert.is_false(state.is_attached(7))
    state.set_attached(7, true)
    assert.is_true(state.is_attached(7))
    state.set_attached(7, false)
    assert.is_false(state.is_attached(7))
  end)

  it("preview_windows_for lists only preview-mode windows showing the buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local other = vim.api.nvim_create_buf(false, true)
    local preview_win = open_window(buf)
    local raw_win = open_window(buf)
    local other_win = open_window(other)
    vim.list_extend(opened, { preview_win, raw_win, other_win })

    state.set_window(preview_win, entry("preview", buf))
    state.set_window(raw_win, entry("markdown", buf))
    state.set_window(other_win, entry("preview", other))

    assert.are.same({ preview_win }, state.preview_windows_for(buf))
    assert.are.same({ other_win }, state.preview_windows_for(other))
  end)

  it("preview_windows_for skips windows that no longer exist", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = open_window(buf)
    state.set_window(win, entry("preview"))
    vim.api.nvim_win_close(win, true)
    assert.are.same({}, state.preview_windows_for(buf))
  end)

  it("preview_windows_for returns an empty list for an unknown buffer", function()
    assert.are.same({}, state.preview_windows_for(123456))
  end)

  it("snapshot returns a deep copy", function()
    local win = 1004
    state.set_window(win, entry("markdown"))
    state.set_attached(5, true)
    local snap = state.snapshot()
    assert.equals("markdown", snap.windows[win].mode)
    assert.is_true(snap.attached[5])
    snap.windows[win].mode = "preview"
    snap.attached[5] = nil
    snap.windows[2000] = entry("preview")
    assert.equals("markdown", state.mode(win))
    assert.is_true(state.is_attached(5))
    assert.is_nil(state.mode(2000))
  end)

  it("reset clears everything", function()
    state.set_window(1005, entry("preview"))
    state.set_attached(6, true)
    state.reset()
    assert.are.same({ windows = {}, attached = {} }, state.snapshot())
    assert.is_nil(state.mode(1005))
    assert.is_false(state.is_attached(6))
  end)
end)
