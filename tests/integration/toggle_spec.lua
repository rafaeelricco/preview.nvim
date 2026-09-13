local FIXTURE = vim.fn.fnamemodify("tests/fixtures/elements.md", ":p")

--- Used only when the fixture file is missing.
local FALLBACK_LINES = {
  "# Heading one",
  "## Heading two",
  "",
  "Some **bold** and *italic* words.",
  "",
  "- top level",
  "  - second level",
}

--- Every window option preview mode touches.
---@type string[]
local OPTION_KEYS = {
  "conceallevel",
  "concealcursor",
  "number",
  "relativenumber",
  "signcolumn",
  "cursorline",
  "colorcolumn",
  "foldcolumn",
  "foldenable",
  "linebreak",
  "breakindent",
  "breakindentopt",
  "showbreak",
  "list",
}

--- Every notification captured while `vim.notify` is stubbed.
---@type { msg: string, level: integer }[]
local notifications = {}
local original_notify = vim.notify

--- Forgets every loaded preview module so each test gets fresh module state.
local function unload_preview()
  for key in pairs(package.loaded) do
    if key == "preview" or vim.startswith(key, "preview.") then
      package.loaded[key] = nil
    end
  end
end

--- Opens the fixture (or a scratch fallback) in the current window and fires FileType.
---@return integer win, integer buf
local function open_fixture()
  if vim.fn.filereadable(FIXTURE) == 1 then
    vim.cmd.edit(FIXTURE)
  else
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, FALLBACK_LINES)
  end
  -- Setting the option fires FileType even when detection already set it.
  vim.bo.filetype = "markdown"
  return vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
end

--- Loads the plugin with `opts` and returns the modules the assertions read.
---@param opts table|nil
local function load(opts)
  local preview = require("preview")
  preview.setup(opts or {})
  return preview, require("preview.state"), require("preview.ui.winbar")
end

---@param level integer
---@param needle string
---@return boolean
local function notified(level, needle)
  for _, entry in ipairs(notifications) do
    if entry.level == level and entry.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("preview toggle", function()
  before_each(function()
    -- Let the previous test's augroup release its windows before forgetting it.
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
    local ok, state = pcall(require, "preview.state")
    if ok then
      state.reset()
    end
    unload_preview()
    notifications = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      notifications[#notifications + 1] = { msg = msg, level = level }
    end
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  it("installs the winbar and default mode on a markdown window", function()
    local preview, _, winbar = load()
    local win = open_fixture()
    assert.equals(winbar.EXPR, vim.wo[win].winbar)
    assert.equals("markdown", preview.mode(win))
  end)

  it("manages markdown windows that were visible before setup", function()
    local win = open_fixture()
    local preview, _, winbar = load()
    assert.equals(winbar.EXPR, vim.wo[win].winbar)
    assert.equals("markdown", preview.mode(win))
  end)

  it("defines the buffer-local toggle keymap", function()
    load()
    open_fixture()
    local map = vim.fn.maparg("<leader>tp", "n", false, true)
    assert.equals(1, map.buffer)
    assert.equals("[T]oggle [P]review", map.desc)
  end)

  it("skips the keymap when keymap is false", function()
    load({ keymap = false })
    open_fixture()
    local map = vim.fn.maparg("<leader>tp", "n", false, true)
    assert.is_nil(map.buffer)
  end)

  it("sets conceallevel 2 and attaches the renderer in preview mode", function()
    local preview, state = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    assert.equals("preview", preview.mode(win))
    assert.equals(2, vim.wo[win].conceallevel)
    assert.is_true(state.is_attached(buf))
  end)

  it("starts a second window on the same buffer in markdown mode", function()
    local preview, state = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    assert.equals("markdown", preview.mode(win2))
    assert.equals("preview", preview.mode(win))
    assert.is_true(state.is_attached(buf))
  end)

  it("resets an inherited conceallevel so a split window shows raw markdown", function()
    local preview = load()
    local win = open_fixture()
    vim.wo[win].conceallevel = 0
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    assert.equals("markdown", preview.mode(win2))
    assert.equals(0, vim.wo[win2].conceallevel)
    preview.set_mode(win2, "preview")
    preview.set_mode(win2, "markdown")
    assert.equals(0, vim.wo[win2].conceallevel)
  end)

  it("restores the saved conceallevel when leaving preview", function()
    local preview, state = load()
    local win, buf = open_fixture()
    vim.wo[win].conceallevel = 1
    preview.set_mode(win, "preview")
    assert.equals(2, vim.wo[win].conceallevel)
    preview.set_mode(win, "markdown")
    assert.equals(1, vim.wo[win].conceallevel)
    assert.is_false(state.is_attached(buf))
  end)

  it("toggle defaults to the current window", function()
    local preview = load()
    local win = open_fixture()
    preview.toggle()
    assert.equals("preview", preview.mode(win))
    preview.toggle()
    assert.equals("markdown", preview.mode(win))
  end)

  it("detaches when the only preview window closes", function()
    local preview, state = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    assert.is_false(state.is_attached(buf))
    assert.is_nil(state.snapshot().windows[win])
    assert.equals("markdown", preview.mode(win2))
  end)

  it("stays attached while another preview window remains", function()
    local preview, state = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    preview.set_mode(win2, "preview")
    vim.api.nvim_win_close(win2, true)
    assert.is_true(state.is_attached(buf))
    assert.equals("preview", preview.mode(win))
  end)

  it("releases a managed window that switches to a non-markdown buffer", function()
    local preview = load()
    local win = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd.enew()
    assert.is_nil(preview.mode(win))
    assert.equals("", vim.wo[win].winbar)
  end)

  it("clears state on BufWipeout", function()
    local preview, state = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd("bwipeout!")
    assert.is_false(state.is_attached(buf))
    assert.is_nil(next(state.snapshot().windows))
  end)

  it("ignores set_mode on an unmanaged window", function()
    local preview, state = load()
    vim.cmd.enew()
    local win = vim.api.nvim_get_current_win()
    local before = vim.wo[win].conceallevel
    preview.set_mode(win, "preview")
    assert.is_nil(preview.mode(win))
    assert.equals(before, vim.wo[win].conceallevel)
    assert.is_nil(next(state.snapshot().attached))
  end)

  it("runs the :Preview subcommands", function()
    local preview = load()
    local win = open_fixture()
    vim.cmd("Preview preview")
    assert.equals("preview", preview.mode(win))
    vim.cmd("Preview toggle")
    assert.equals("markdown", preview.mode(win))
    vim.cmd("Preview toggle")
    assert.equals("preview", preview.mode(win))
    vim.cmd("Preview markdown")
    assert.equals("markdown", preview.mode(win))
  end)

  it("reports an unknown :Preview subcommand without throwing", function()
    local preview = load()
    local win = open_fixture()
    assert.is_true(pcall(function()
      vim.cmd("Preview bogus")
    end))
    assert.equals("markdown", preview.mode(win))
    assert.is_true(notified(vim.log.levels.ERROR, "bogus"))
  end)

  it("reports an unknown set_mode mode without throwing", function()
    local preview = load()
    local win = open_fixture()
    local winbar_before = vim.wo[win].winbar
    local conceal_before = vim.wo[win].conceallevel
    assert.is_true(pcall(preview.set_mode, win, "bogus"))
    assert.equals("markdown", preview.mode(win))
    assert.equals(winbar_before, vim.wo[win].winbar)
    assert.equals(conceal_before, vim.wo[win].conceallevel)
    assert.is_true(notified(vim.log.levels.ERROR, "bogus"))
  end)

  it("keeps modes working when the winbar is disabled", function()
    local preview, state = load({ winbar = { enabled = false } })
    local win, buf = open_fixture()
    assert.equals("", vim.wo[win].winbar)
    preview.set_mode(win, "preview")
    assert.equals(2, vim.wo[win].conceallevel)
    assert.is_true(state.is_attached(buf))
  end)

  it("reconfigures controls while preserving mode and owned baselines", function()
    local preview, _, winbar = load({
      winbar = { enabled = false }, keymap = false,
    })
    local win, buf = open_fixture()
    vim.wo[win].winbar = "original"
    vim.wo[win].winhighlight = "WinBar:ErrorMsg,LineNr:Comment"
    vim.wo[win].wrap = false
    preview.set_mode(win, "preview")

    preview.setup({ keymap = "gp" })
    assert.equals(winbar.EXPR, vim.wo[win].winbar)
    assert.equals("[T]oggle [P]review", vim.fn.maparg("gp", "n", false, true).desc)
    preview.setup({ keymap = "gP" })
    assert.equals("", vim.fn.maparg("gp", "n"))
    assert.equals("[T]oggle [P]review", vim.fn.maparg("gP", "n", false, true).desc)

    preview.setup({ winbar = { enabled = false }, keymap = false })
    assert.equals("original", vim.wo[win].winbar)
    assert.equals("", vim.fn.maparg("gP", "n"))
    assert.is_true(vim.wo[win].winhighlight:find("WinBar:ErrorMsg", 1, true) ~= nil)
    assert.is_true(vim.wo[win].winhighlight:find("LineNr:Comment", 1, true) ~= nil)
    assert.equals("preview", preview.mode(win))

    preview.setup({ keymap = "gp" })
    vim.keymap.set("n", "gp", "<Nop>", { buffer = buf })
    vim.wo[win].winbar = "user replacement"
    preview.setup({ winbar = { enabled = false }, keymap = false })
    assert.equals("<Nop>", vim.fn.maparg("gp", "n"))
    assert.equals("user replacement", vim.wo[win].winbar)
    preview.set_mode(win, "markdown")
    assert.equals(false, vim.wo[win].wrap)
  end)

  it("exposes a copy of the resolved config", function()
    local preview = load()
    local cfg = preview.config()
    assert.is_not_nil(cfg)
    assert.equals("markdown", cfg.default_mode)
    cfg.default_mode = "preview"
    assert.equals("markdown", preview.config().default_mode)
  end)

  it("records the pre-preview conceallevel in saved_options", function()
    local preview, state = load()
    local win = open_fixture()
    vim.wo[win].conceallevel = 1
    preview.set_mode(win, "preview")
    assert.equals(1, state.snapshot().windows[win].saved_options.conceallevel)
  end)

  it("applies the reading-view window and buffer options in preview mode", function()
    local preview = load()
    local win = open_fixture()
    vim.wo[win].number = true
    vim.wo[win].relativenumber = true
    vim.wo[win].wrap = false
    preview.set_mode(win, "preview")
    assert.equals(false, vim.wo[win].number)
    assert.equals(false, vim.wo[win].relativenumber)
    assert.equals("no", vim.wo[win].signcolumn)
    assert.equals(false, vim.wo[win].cursorline)
    assert.equals("0", vim.wo[win].foldcolumn)
    assert.equals(false, vim.wo[win].foldenable)
    assert.equals(false, vim.wo[win].wrap)
    assert.equals(false, vim.wo[win].linebreak)
    assert.equals(false, vim.wo[win].breakindent)
    assert.equals("", vim.wo[win].breakindentopt)
    assert.equals("", vim.wo[win].showbreak)
    assert.equals(false, vim.wo[win].list)
    assert.equals(2, vim.wo[win].conceallevel)
    assert.equals("nvic", vim.wo[win].concealcursor)
  end)

  it("restores every window option exactly when leaving preview", function()
    local preview = load()
    local win = open_fixture()
    vim.wo[win].number = true
    vim.wo[win].signcolumn = "yes"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    local before = {}
    for _, key in ipairs(OPTION_KEYS) do
      before[key] = vim.wo[win][key]
    end
    preview.set_mode(win, "preview")
    preview.set_mode(win, "markdown")
    for _, key in ipairs(OPTION_KEYS) do
      assert.equals(before[key], vim.wo[win][key])
    end
    assert.equals(true, vim.wo[win].number)
    assert.equals("yes", vim.wo[win].signcolumn)
    assert.equals(false, vim.wo[win].wrap)
    assert.equals(true, vim.wo[win].cursorline)
  end)

  for _, command in ipairs({ "vsplit", "tab split" }) do
    it("preserves current raw options through " .. command, function()
      vim.wo.number = false
      vim.wo.wrap = true
      vim.wo.signcolumn = "auto"
      local preview = load()
      open_fixture()
      vim.wo.number = true
      vim.wo.wrap = false
      vim.wo.signcolumn = "yes"
      vim.cmd(command)
      assert.equals("markdown", preview.mode())
      assert.equals(true, vim.wo.number)
      assert.equals(false, vim.wo.wrap)
      assert.equals("yes", vim.wo.signcolumn)
    end)

    it("uses the source preview baseline through " .. command, function()
      local preview = load()
      local first = open_fixture()
      vim.cmd.vsplit()
      local second = vim.api.nvim_get_current_win()
      for _, entry in ipairs({
        { win = first, number = false, wrap = true },
        { win = second, number = true, wrap = false },
      }) do
        vim.api.nvim_set_current_win(entry.win)
        vim.wo.number = entry.number
        vim.wo.wrap = entry.wrap
        preview.set_mode(entry.win, "preview")
      end
      for _, entry in ipairs({
        { win = first, number = false, wrap = true },
        { win = second, number = true, wrap = false },
      }) do
        vim.api.nvim_set_current_win(entry.win)
        vim.cmd(command)
        assert.equals("markdown", preview.mode())
        assert.equals(entry.number, vim.wo.number)
        assert.equals(entry.wrap, vim.wo.wrap)
        vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
      end
    end)
  end

  it("gives a window split from a preview window the baseline options", function()
    local preview = load()
    local win = open_fixture()
    vim.wo[win].number = true
    vim.wo[win].signcolumn = "yes"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.wo[win].foldcolumn = "0"
    local baseline = {}
    for _, key in ipairs(OPTION_KEYS) do
      baseline[key] = vim.wo[win][key]
    end
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    assert.equals("markdown", preview.mode(win2))
    for _, key in ipairs(OPTION_KEYS) do
      assert.equals(baseline[key], vim.wo[win2][key])
    end
    assert.equals(true, vim.wo[win2].number)
    assert.equals("yes", vim.wo[win2].signcolumn)
    assert.equals(false, vim.wo[win2].wrap)
    assert.equals(true, vim.wo[win2].cursorline)
    assert.equals("0", vim.wo[win2].foldcolumn)
    assert.equals("preview", preview.mode(win))
    assert.equals(false, vim.wo[win].wrap)
  end)

  it("never mutates the shared buffer formatlistpat", function()
    local preview, state = load()
    local win, buf = open_fixture()
    vim.bo[buf].formatlistpat = [[^\s*\d\+[\]:.)}\t ]\s*]]
    preview.set_mode(win, "preview")
    vim.cmd.vsplit()
    local win2 = vim.api.nvim_get_current_win()
    preview.set_mode(win2, "preview")
    assert.equals([[^\s*\d\+[\]:.)}\t ]\s*]], vim.bo[buf].formatlistpat)
    preview.set_mode(win, "markdown")
    assert.equals([[^\s*\d\+[\]:.)}\t ]\s*]], vim.bo[buf].formatlistpat)
    preview.set_mode(win2, "markdown")
    assert.is_false(state.is_attached(buf))
    assert.equals([[^\s*\d\+[\]:.)}\t ]\s*]], vim.bo[buf].formatlistpat)
  end)

  it("keeps the window's nowrap without using foldcolumn for layout", function()
    local preview = load({ view = { gutter = 2 } })
    local win = open_fixture()
    vim.wo[win].wrap = false
    preview.set_mode(win, "preview")
    assert.equals("0", vim.wo[win].foldcolumn)
    assert.equals(false, vim.wo[win].wrap)
  end)

  for _, case in ipairs({ { view = true, window = false }, { view = false, window = true } }) do
    it(("forces view.wrap = %s in preview and restores the window's own"):format(tostring(case.view)), function()
      local preview = load({ view = { wrap = case.view } })
      local win = open_fixture()
      vim.wo[win].wrap = case.window
      preview.set_mode(win, "preview")
      assert.equals(case.view, vim.wo[win].wrap)
      preview.set_mode(win, "markdown")
      assert.equals(case.window, vim.wo[win].wrap)
    end)
  end

  it("restores a wrap that a setup() re-run starts forcing mid-preview", function()
    local preview = load()
    local win = open_fixture()
    vim.wo[win].wrap = false
    preview.set_mode(win, "preview")
    preview.setup({ view = { wrap = true } })
    assert.equals(true, vim.wo[win].wrap)
    preview.set_mode(win, "markdown")
    assert.equals(false, vim.wo[win].wrap)
  end)

  it("keeps a preview window intact while focus visits another buffer", function()
    local preview, state, winbar = load()
    local win, buf = open_fixture()
    preview.set_mode(win, "preview")
    vim.cmd("topleft vnew")
    vim.api.nvim_set_current_win(win)
    vim.cmd.wincmd("h")
    assert.equals(2, vim.wo[win].conceallevel)
    assert.equals(winbar.EXPR, vim.wo[win].winbar)
    assert.equals(1, #state.preview_windows_for(buf))
  end)

  it("drops conceal_lines from the markdown highlight query", function()
    load()
    local query = vim.treesitter.query.get("markdown", "highlights")
    -- `has_conceal_line` is the compiled flag that removes a fence row from the
    -- display; the whole fix is that it must no longer be set.
    assert.is_nil(query.has_conceal_line)
  end)

  it("leaves another plugin's markdown highlight query untouched", function()
    -- Neovim keeps no reader for an explicitly set query, so overwriting one
    -- would discard it for the session with no way to restore it. Better to
    -- skip the workaround than to silently break someone else's highlighting.
    local files = vim.treesitter.query.get_files("markdown", "highlights")
    local parts = {}
    for _, path in ipairs(files) do
      local handle = assert(io.open(path, "r"))
      parts[#parts + 1] = handle:read("*a")
      handle:close()
    end
    local foreign = table.concat(parts) .. "\n((atx_heading) @preview.spec.marker)\n"
    vim.treesitter.query.set("markdown", "highlights", foreign)

    local function has_marker()
      for _, capture in ipairs(vim.treesitter.query.get("markdown", "highlights").captures) do
        if capture == "preview.spec.marker" then
          return true
        end
      end
      return false
    end
    assert.is_true(has_marker())

    load()

    assert.is_true(has_marker())
    assert.is_true(notified(vim.log.levels.WARN, "another markdown highlights query"))
    vim.treesitter.query.set("markdown", "highlights", nil)
  end)

  it("restarts only the markdown highlighters that were already running", function()
    -- Rebuilding is required because a highlighter latches the old query's
    -- conceal_lines flag at attach, but starting one where the user turned
    -- Treesitter highlighting off would enable a feature they disabled.
    local active = vim.treesitter.highlighter.active

    local stopped = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(stopped, 0, -1, false, { "# heading" })
    vim.bo[stopped].filetype = "markdown"
    vim.treesitter.start(stopped, "markdown")
    vim.treesitter.stop(stopped)

    local never = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(never, 0, -1, false, { "# heading" })
    vim.bo[never].filetype = "markdown"

    local running = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(running, 0, -1, false, { "# heading" })
    vim.bo[running].filetype = "markdown"
    vim.treesitter.start(running, "markdown")

    load()

    assert.is_nil(active[stopped])
    assert.is_nil(active[never])
    assert.is_not_nil(active[running])
  end)
end)
