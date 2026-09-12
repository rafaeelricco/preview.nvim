local screen = require("tests.screen")

describe("preview composed screen", function()
  local ui
  before_each(function()
    ui = screen.new(60, 24)
  end)
  after_each(function()
    ui.close()
  end)

  local function open(lines, opts)
    ui.exec([[
      local lines, opts = ...
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = 'markdown'
      require('preview').setup(opts)
    ]], { lines, opts or { default_mode = "preview", view = { gutter = 0 } } })
  end

  it("keeps complete checkboxes rendered on the cursor row", function()
    open({ "before", "", "- [x] done", "- [ ] open" }, {
      default_mode = "preview",
      view = { gutter = 0 },
      render = { checkbox = { checked = "C", unchecked = "U" } },
    })
    assert.are.same({ "C done", "U open" }, vim.list_slice(ui.lines(), 4, 5))
    ui.exec("vim.api.nvim_win_set_cursor(0, {3, 0})")
    assert.equals("C done", ui.lines()[4])
    ui.exec("vim.api.nvim_win_set_cursor(0, {4, 0})")
    assert.equals("C done", ui.lines()[4])
    assert.equals("U open", ui.lines()[5])
  end)

  it("displays a complete table without empty wrap rows or lost EOF content", function()
    open({ "before", "", "| Name | Value |", "| --- | --- |", "| alpha | one |", "| beta | two |" })
    local rows = ui.lines()
    assert.are.same({
      "┌───────┬───────┐", "│ Name  │ Value │", "├───────┼───────┤",
      "│ alpha │ one   │", "├───────┼───────┤", "│ beta  │ two   │", "└───────┴───────┘",
    }, vim.list_slice(rows, 4, 10))
  end)

  it("keeps a table free of blank wrap rows when its source is wider than it draws", function()
    open({ "before", "", "| Role | Dates | Stack |", "|---|---|---|",
      "| Ambar (Prevou, Hart) | Sep 2025 - present | React |" })
    assert.are.same({
      "┌──────────────────────┬────────────────────┬───────┐",
      "│ Role                 │ Dates              │ Stack │",
      "├──────────────────────┼────────────────────┼───────┤",
      "│ Ambar (Prevou, Hart) │ Sep 2025 - present │ React │",
      "└──────────────────────┴────────────────────┴───────┘",
    }, vim.list_slice(ui.lines(), 4, 8))
    local attrs = ui.exec("return {vim.fn.screenattr(4, 1), vim.fn.screenattr(5, 1)}")
    assert.equals(attrs[1], attrs[2])
  end)

  it("keeps the table visible when its following anchor is the cursor row", function()
    open({ "before", "| a | b |", "| - | - |", "| one | two |", "", "after" })
    ui.exec("vim.api.nvim_win_set_cursor(0, {5, 0})")
    assert.truthy(table.concat(ui.lines(), "\n"):find("│ one │ two │", 1, true))
    ui.exec("vim.api.nvim_win_set_cursor(0, {4, 0})")
    local text = table.concat(ui.lines(), "\n")
    assert.is_nil(text:find("| one | two |", 1, true))
    assert.truthy(text:find("│ one │ two │", 1, true))
    assert.truthy(text:find("│ a   │ b   │", 1, true))
  end)

  it("reinstalls the bar and keymap for another Markdown buffer", function()
    open({ "source" }, {})
    local result = ui.exec([[
      local original = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_name(original, '/tmp/preview-study.md')
      local next_buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(next_buf, '/tmp/preview-prep.md')
      vim.api.nvim_buf_set_lines(next_buf, 0, -1, false, {'---', '', 'plain text'})
      vim.api.nvim_win_set_buf(0, next_buf)
      return {bar=vim.wo.winbar, mode=require('preview').mode(),
        key=vim.fn.maparg('<leader>tp', 'n', false, true).desc}
    ]])
    assert.equals(require("preview.ui.winbar").EXPR, result.bar)
    assert.equals("markdown", result.mode)
    assert.equals("[T]oggle [P]review", result.key)
    assert.truthy(ui.lines()[1]:find("Preview  Markdown", 1, true))
  end)

  it("switches between editable stacked fields and a grid on resize", function()
    local lines = { "before", "| a | b |", "| - | - |", "| alpha | one two three four five six seven eight nine ten |", "", "after" }
    open(lines)
    ui.resize(30, 24)
    local text = table.concat(ui.lines(), "\n")
    assert.truthy(text:find("a: alpha", 1, true))
    assert.is_nil(text:find("| alpha", 1, true))
    assert.are.same(lines, ui.exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    ui.resize(8, 24)
    assert.is_nil(table.concat(ui.lines(), "\n"):find("| alpha", 1, true))
    assert.are.same({}, ui.exec("return _G.notifications"))
    ui.resize(100, 24)
    ui.exec("vim.cmd('normal! gg')")
    assert.truthy(table.concat(ui.lines(), "\n"):find("┌", 1, true))
    assert.are.same(lines, ui.exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  end)

  it("isolates raw and preview splits and fits each preview window independently", function()
    open({ "before", "", "| Name | Value |", "| --- | --- |", "| alpha | one |", "", "after" },
      {view={gutter=4,max_width=100}})
    ui.exec([[
      _G.right = vim.api.nvim_get_current_win()
      require('preview').set_mode(_G.right, 'preview')
      vim.cmd('vsplit')
      _G.left = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_width(_G.left, 24)
    ]])
    local function contents()
      ui.redraw()
      return ui.exec([[
        local out = {}
        for _, win in ipairs({_G.left, _G.right}) do
          local info = vim.fn.getwininfo(win)[1]
          local rows = {}
          for r = 1, 20 do
            local cells = {}
            for c = info.wincol, info.wincol + info.width - 1 do cells[#cells + 1] = vim.fn.screenstring(r, c) end
            rows[#rows + 1] = table.concat(cells)
          end
          out[#out + 1] = {text=table.concat(rows, '\n'), width=info.width-info.textoff}
        end
        return out
      ]])
    end
    local split = contents()
    assert.truthy(split[1].text:find("| Name | Value |", 1, true))
    assert.is_nil(split[1].text:find("┌", 1, true))
    assert.truthy(split[2].text:find("┌", 1, true))
    ui.exec("require('preview').set_mode(_G.left, 'preview')")
    split = contents()
    assert.truthy(split[1].text:find("Name: alpha", 1, true))
    assert.truthy(split[2].text:find("│ alpha │ one   │", 1, true))
    ui.exec("require('preview').set_mode(_G.right, 'markdown')")
    split = contents()
    assert.truthy(split[1].text:find("Name: alpha", 1, true))
    assert.is_nil(split[2].text:find("┌", 1, true))
  end)

  it("displays heading spacing, code panels and a single screen row for a rule", function()
    ui.exec([[
      vim.api.nvim_set_hl(0, 'Normal', {fg=0xeeeeee, bg=0x181818})
      vim.api.nvim_set_hl(0, 'CursorLine', {bg=0x262626})
    ]])
    open({ "before", "", "## Heading", "", "```", "code panel", "```", "", "---", "", "after" })
    local rows = ui.lines()
    local heading, code, rule
    for i, line in ipairs(rows) do
      if line == "Heading" then heading = i end
      if vim.trim(line) == "code panel" then code = i end
      if line == ("─"):rep(60) then rule = i end
    end
    assert.equals(5, heading)
    assert.is_not_nil(code)
    assert.is_not_nil(rule)
    assert.equals("", rows[rule + 1])
    assert.equals("after", rows[rule + 2])
    local attrs = ui.exec("local code = ...; return {vim.fn.screenattr(code, 40), vim.fn.screenattr(2, 40)}", { code })
    assert.are_not.equals(attrs[1], attrs[2])
  end)

  it("uses file extensions even for empty files or a different detected filetype", function()
    ui.exec("require('preview').setup({})")
    for _, name in ipairs({ "empty.md", "plain.MD", "notes.Markdown" }) do
      local result = ui.exec([[
        local name = ...
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/tmp/preview-' .. name)
        vim.bo[buf].filetype = 'text'
        vim.api.nvim_win_set_buf(0, buf)
        return {mode=require('preview').mode(), bar=vim.wo.winbar}
      ]], { name })
      assert.equals("markdown", result.mode)
      assert.equals(require("preview.ui.winbar").EXPR, result.bar)
      assert.equals(1, ui.exec("return vim.tbl_count(require('preview.state').snapshot().windows)"))
    end
    ui.exec("vim.cmd('file /tmp/preview-renamed.txt'); vim.bo.filetype = 'markdown'")
    assert.equals("", ui.exec("return vim.wo.winbar"))
    assert.equals(vim.NIL, ui.exec("return require('preview').mode()"))
    assert.equals("", ui.exec("return vim.fn.maparg('<leader>tp', 'n')"))
    ui.exec("vim.cmd('file /tmp/preview-renamed.md')")
    assert.equals("markdown", ui.exec("return require('preview').mode()"))
    assert.truthy(ui.lines()[1]:find("Preview", 1, true))
    ui.exec([[
      vim.bo.filetype = 'text'
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {'before', '', '## Heading'})
      require('preview').toggle()
      vim.cmd('file /tmp/preview-renamed.Markdown')
    ]])
    assert.equals("preview", ui.exec("return require('preview').mode()"))
    assert.equals("Heading", vim.trim(ui.lines()[5]))
  end)

  it("preserves each buffer's baseline and selected mode through A to B to A", function()
    open({ "source A" }, {})
    local result = ui.exec([[
      local preview = require('preview')
      local a = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_name(a, '/tmp/preview-A.md')
      vim.wo.wrap = false; vim.wo.conceallevel = 1
      local b = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(b, '/tmp/preview-B.md')
      vim.api.nvim_win_set_buf(0, b)
      vim.wo.wrap = true; vim.wo.conceallevel = 0
      vim.api.nvim_win_set_buf(0, a)
      preview.set_mode(vim.api.nvim_get_current_win(), 'preview')
      vim.api.nvim_win_set_buf(0, b)
      local entered = preview.mode()
      preview.set_mode(vim.api.nvim_get_current_win(), 'markdown')
      local baseline_b = {wrap=vim.wo.wrap, conceal=vim.wo.conceallevel}
      vim.api.nvim_win_set_buf(0, a)
      return {entered=entered, b=baseline_b, a={wrap=vim.wo.wrap, conceal=vim.wo.conceallevel},
        attached=require('preview.state').snapshot().attached}
    ]])
    assert.equals("preview", result.entered)
    assert.are.same({ wrap = true, conceal = 0 }, result.b)
    assert.are.same({ wrap = false, conceal = 1 }, result.a)
    assert.is_nil(next(result.attached))
  end)

  it("keeps previews on focus changes and cleans up a noncurrent buffer switch", function()
    open({ "before", "| a | b |", "| - | - |", "| one | two |", "", "after" }, {})
    ui.exec([[
      _G.original = vim.api.nvim_get_current_win()
      require('preview').set_mode(_G.original, 'preview')
      vim.cmd('vsplit')
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, '/tmp/preview-focus.md')
      vim.api.nvim_win_set_buf(0, buf)
    ]])
    assert.truthy(table.concat(ui.lines(), "\n"):find("│ one │ two │", 1, true))
    assert.equals(2, ui.exec("return vim.wo[_G.original].conceallevel"))
    ui.exec([[
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, '/tmp/preview-other.txt')
      vim.api.nvim_win_set_buf(_G.original, buf)
    ]])
    assert.is_nil(table.concat(ui.lines(), "\n"):find("┌", 1, true))
    assert.equals(vim.NIL, ui.exec("return require('preview').mode(_G.original)"))
  end)

  it("uses the transparent theme base and restores only owned bar mappings", function()
    ui.exec([[
      vim.api.nvim_set_hl(0, 'Normal', {fg=0xf0f0f0})
      vim.api.nvim_set_hl(0, 'Comment', {fg=0x888888})
      vim.api.nvim_set_hl(0, 'CursorLine', {bg=0x262626})
      vim.api.nvim_set_hl(0, 'WinBar', {bg=0x07080d, bold=true})
      vim.wo.winhighlight='Normal:Normal,WinBar:ErrorMsg'
    ]])
    open({ "source" }, {})
    ui.redraw()
    local before = ui.exec("return vim.fn.screenattr(1, 1)")
    ui.exec("vim.api.nvim_set_hl(0, 'WinBar', {bg=0xff0000, reverse=true})")
    ui.redraw()
    assert.equals(before, ui.exec("return vim.fn.screenattr(1, 1)"))
    ui.exec([[
      vim.wo.winhighlight = vim.wo.winhighlight .. ',LineNr:Comment'
      vim.api.nvim_buf_set_name(0, '/tmp/preview-release.txt')
    ]])
    local mappings = ui.exec("return vim.wo.winhighlight")
    assert.truthy(mappings:find("WinBar:ErrorMsg", 1, true))
    assert.truthy(mappings:find("LineNr:Comment", 1, true))
    assert.is_nil(mappings:find("WinBarNC:Normal", 1, true))
  end)

  it("refreshes controls on light/dark events and preserves explicit overrides", function()
    open({ "source" }, { highlights = { PreviewLink = { fg = 0x123456 } } })
    for _, palette in ipairs({ { 0x111111, 0xeeeeee }, { 0xf0f0f0, 0x262626 } }) do
      ui.exec([[
        local fg, panel = ...
        vim.api.nvim_set_hl(0, 'Normal', {fg=fg})
        vim.api.nvim_set_hl(0, 'CursorLine', {bg=panel})
        vim.api.nvim_exec_autocmds('ColorScheme', {pattern='probe'})
      ]], palette)
      ui.redraw()
      local result = ui.exec([[
        return {active=vim.api.nvim_get_hl(0, {name='PreviewButtonActive'}),
          link=vim.api.nvim_get_hl(0, {name='PreviewLink'})}
      ]])
      assert.equals(palette[1], result.active.fg)
      assert.equals(palette[2], result.active.bg)
      assert.is_nil(result.active.reverse)
      assert.equals(0x123456, result.link.fg)
    end
  end)

  it("keeps source visible after a placement failure and reports the failure once", function()
    ui.exec([[
      _G.warnings = 0
      vim.notify_once = function() _G.warnings = _G.warnings + 1 end
      local original = vim.api.nvim_buf_set_extmark
      vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
        if opts.virt_lines then error('screen test placement failure') end
        return original(buf, ns, row, col, opts)
      end
    ]])
    open({ "before", "| a | b |", "| - | - |", "| one | two |", "", "after" })
    local text = table.concat(ui.lines(), "\n")
    assert.truthy(text:find("| a | b |", 1, true))
    assert.truthy(text:find("| one | two |", 1, true))
    ui.redraw()
    assert.equals(1, ui.exec("return _G.warnings"))
  end)

  it("does not replace stored marks on an unchanged redraw", function()
    ui.exec([[
      _G.placements = 0
      local original = vim.api.nvim_buf_set_extmark
      vim.api.nvim_buf_set_extmark = function(buf, ns, ...)
        local namespace = 'preview.nvim.window.' .. vim.api.nvim_get_current_win()
        if ns == vim.api.nvim_get_namespaces()[namespace] then
          _G.placements = _G.placements + 1
        end
        return original(buf, ns, ...)
      end
    ]])
    open({ "before", "| a | b |", "| - | - |", "| one | two |", "", "after" })
    ui.redraw()
    local count = ui.exec("return _G.placements")
    assert.is_true(count > 0)
    ui.redraw()
    assert.equals(count, ui.exec("return _G.placements"))
    ui.exec("vim.api.nvim_win_set_cursor(0, {4, 2})")
    ui.redraw()
    assert.equals(count, ui.exec("return _G.placements"))
    ui.exec("vim.api.nvim_buf_set_lines(0, 3, 4, false, {'| changed | value |'})")
    assert.truthy(table.concat(ui.lines(), "\n"):find("changed", 1, true))
    assert.is_true(ui.exec("return _G.placements") > count)
  end)

  it("keeps the view still when focus moves to another window", function()
    ui.resize(160, 45)
    local lines = {}
    for _ = 1, 10 do
      vim.list_extend(lines, vim.fn.readfile("tests/fixtures/reading-view.md"))
    end
    ui.exec("vim.o.number, vim.o.signcolumn, vim.o.cursorline, vim.o.scrolloff = true, 'yes', true, 8")
    open(lines, { default_mode = "preview" })
    ui.exec("vim.cmd('topleft 30vnew | wincmd p')")
    for _, place in ipairs({ "20Gzt", "70Gzt", "95Gzt", "120Gzz", "220Gzb", "245Gzt" }) do
      ui.exec("vim.cmd('normal! " .. place .. "')")
      local before = ui.lines()
      ui.exec("vim.cmd.wincmd('h')")
      assert.are.same(before, ui.lines(), place)
      ui.exec("vim.cmd.wincmd('l')")
    end
  end)

  it("tapers the gap above each heading level", function()
    open({ "# One", "", "## Two", "", "### Three", "", "#### Four", "", "##### Five", "", "###### Six", "", "text" })
    -- Row 1 is the winbar. A document-opening heading takes no leading gap, and
    -- the source blank between every pair is replaced by the designed one.
    assert.are.same({
      "One", "", "", "Two", "", "", "Three", "", "Four", "", "Five", "", "Six", "", "text",
    }, vim.list_slice(ui.lines(), 2, 16))
  end)

  it("keeps adjacent code panels apart instead of merging them into one slab", function()
    open({ "before", "", "```lua", "a()", "```", "", "```", "b()", "```", "", "after" })
    assert.are.same({
      "before", "", "", "  a()", "", "", "", "  b()", "", "", "after",
    }, vim.list_slice(ui.lines(), 2, 12))
    -- Row 7 carries the plain background, so the two panels read as two
    -- blocks. Without it their padding rows touch and look like one panel.
    local attrs = ui.exec([[return {
      vim.fn.screenattr(6, 1), vim.fn.screenattr(7, 1),
      vim.fn.screenattr(8, 1), vim.fn.screenattr(3, 1) }]])
    assert.equals(attrs[1], attrs[3])
    assert.equals(attrs[2], attrs[4])
    assert.are_not.equals(attrs[1], attrs[2])
  end)
end)
