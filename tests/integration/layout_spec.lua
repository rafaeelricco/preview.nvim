local screen = require("tests.screen")

describe("editable reading layout", function()
  local ui
  before_each(function() ui = screen.new(60, 24) end)
  after_each(function() ui.close() end)

  local function open(lines, opts)
    ui.exec([[
      local lines, opts = ...
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = 'markdown'
      require('preview').setup(vim.tbl_deep_extend('force', {
        default_mode='preview', winbar={enabled=false},
        view={max_width=20,gutter=0},
      }, opts or {}))
    ]], { lines, opts or {} })
  end

  it("centers wrapped source without changing its buffer or window", function()
    open({ "abcdefghijklmnopqrstABCDEFGHIJKLMNOPQRST" })
    local expression = [[return {vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(),
      vim.api.nvim_buf_get_lines(0, 0, -1, false)}]]
    local before = ui.exec(expression)
    assert.are.same({
      string.rep(" ", 20) .. "abcdefghijklmnopqrst",
      string.rep(" ", 20) .. "ABCDEFGHIJKLMNOPQRST",
    }, vim.list_slice(ui.lines(), 1, 2))
    assert.are.same(before, ui.exec(expression))
    assert.equals("~", vim.trim(ui.lines()[3]))
  end)

  it("wraps at word boundaries and recenters after a resize", function()
    open({ "one two three four five six seven eight nine ten" })
    local lines = ui.lines()
    assert.equals(string.rep(" ", 20) .. "one two three four", lines[1])
    assert.equals(string.rep(" ", 20) .. "five six seven eight", lines[2])
    assert.equals(string.rep(" ", 20) .. "nine ten", lines[3])
    ui.resize(40, 24)
    assert.equals(string.rep(" ", 10) .. "one two three four", ui.lines()[1])
  end)

  local linked_items = {
    {
      name = "a linked study sheet followed by interviewer",
      source = "- **[Round 2 study sheet](rounds/02-technical/study.md)** ← read this one first: the role, the JD vocabulary, and the interviewer",
      visible = "• Round 2 study sheet ← read this one first: the role, the JD vocabulary, and the interviewer",
    },
    {
      name = "multiple links and emphasis in one list item",
      source = "- **The posting is closed.** The [original URL](https://example.com/jobs/4394499009) returns no longer open. A [related posting](https://example.com/jobs/4378947009) uses established patterns alongside a [practice-level role](https://example.com/jobs/6887c9b9-d880-439c-92cd-23da70b3d973) with more experience. See the [study sheet](rounds/02-technical/study.md).",
      visible = "• The posting is closed. The original URL returns no longer open. A related posting uses established patterns alongside a practice-level role with more experience. See the study sheet.",
    },
    {
      name = "a link destination longer than the window",
      source = "- Read the [study sheet](https://example.com/" .. string.rep("hidden/", 60) .. ") before meeting the interviewer and discussing the technical role.",
      visible = "• Read the study sheet before meeting the interviewer and discussing the technical role.",
    },
  }

  for _, item in ipairs(linked_items) do
    it("keeps " .. item.name .. " aligned across resizes", function()
      for _, view in ipairs({{max_width=100,gutter=4}, {max_width=0,gutter=2}}) do
        ui.resize(150,80)
        open({item.source}, {view=view})
        local identity = ui.exec("return {vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf()}")
        for _, window_width in ipairs({150,120,60,150}) do
          ui.resize(window_width,80)
          local width, left = require("preview.render.layout").geometry(window_width,
            {wrap=true,center=true,gutter=view.gutter,max_width=view.max_width})
          local text = {}
          for _, line in ipairs(ui.lines()) do
            if vim.trim(line) ~= "" and vim.trim(line) ~= "~" then
              local indent = left + (#text > 0 and 2 or 0)
              assert.equals(string.rep(" ",indent),line:sub(1,indent))
              assert.is_nil(line:sub(indent+1,indent+1):match("%s"))
              assert.is_true(vim.fn.strdisplaywidth(line) <= left+width)
              text[#text+1] = vim.trim(line)
            end
          end
          assert.equals(item.visible,table.concat(text," "))
          assert.are.same({item.source},ui.exec("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
          assert.are.same(identity,ui.exec("return {vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf()}"))
        end
      end
    end)
  end

  it("keeps emphasis concealed while typing, selecting, searching and undoing", function()
    open({ "Some **bold** and _italic_." }, {view={max_width=0}})
    assert.equals("Some bold and italic.", ui.lines()[1])
    ui.exec("vim.api.nvim_win_set_cursor(0, {1, 9})")
    ui.request("nvim_input", "iX")
    ui.redraw()
    assert.equals("Some boXld and italic.", ui.lines()[1])
    ui.request("nvim_input", "<Esc>")
    ui.redraw()
    ui.request("nvim_input", "u")
    assert.equals("Some bold and italic.", ui.lines()[1])
    assert.are.same({"Some **bold** and _italic_."}, ui.exec("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
    ui.request("nvim_input", "vll")
    assert.equals("Some bold and italic.", ui.lines()[1])
    ui.request("nvim_input", "<Esc>/bold")
    assert.equals("Some bold and italic.", ui.lines()[1])
    ui.request("nvim_input", "<Esc>")
  end)

  it("does not wrap or center when the window has nowrap", function()
    ui.exec("vim.wo.wrap = false")
    open({ "one two three four five six seven eight nine ten" }, {view={gutter=2}})
    assert.equals("  one two three four five six seven eight nine ten", ui.lines()[1])
    assert.equals("~", vim.trim(ui.lines()[2]))
  end)

  it("re-lays out when the window's wrap changes in preview", function()
    ui.exec("vim.wo.wrap = false")
    open({ "one two three four five six seven eight nine ten" })
    assert.equals("one two three four five six seven eight nine ten", ui.lines()[1])
    ui.exec("vim.wo.wrap = true")
    assert.equals(string.rep(" ", 20) .. "one two three four", ui.lines()[1])
    ui.exec("vim.wo.wrap = false")
    assert.equals("one two three four five six seven eight nine ten", ui.lines()[1])
  end)

  it("wraps a nowrap window when view.wrap = true forces it in preview", function()
    ui.exec("vim.wo.wrap = false")
    open({ "one two three four five six seven eight nine ten" }, {view={wrap=true}})
    local lines = ui.lines()
    assert.equals(string.rep(" ", 20) .. "one two three four", lines[1])
    assert.equals(string.rep(" ", 20) .. "five six seven eight", lines[2])
  end)

  it("keeps table rules and code padding aligned after a nowrap window scrolls right", function()
    ui.exec("vim.wo.wrap = false")
    open({
      "| Name | Value |", "| --- | --- |",
      "| alpha | one two three four five six seven eight nine ten |",
      "", "```", "code", "```", "",
      "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen",
    }, { view = { gutter = 0, max_width = 0 } })
    ui.exec("vim.api.nvim_win_set_cursor(0, {9, 80})")
    assert.is_true(ui.exec("return vim.fn.winsaveview().leftcol") > 0)
    local rows = ui.lines()
    -- the right edge of the delimiter rule (buffer text), body row and virtual
    -- bottom rule sit in the same screen column
    local function edge(line, char)
      return vim.fn.strdisplaywidth(line:sub(1, line:find(char, 1, true) - 1)) + 1
    end
    assert.equals(edge(rows[2], "┤"), edge(rows[4], "┘"))
    assert.equals(edge(rows[2], "┤"), edge(rows[3], "│"))
    -- the code panel's virtual padding rows and its text row end together
    local panel = ui.exec([[
      local out = {}
      for _, r in ipairs({ 6, 7, 8 }) do
        local first, c = vim.fn.screenattr(r, 1), 1
        while c < 60 and vim.fn.screenattr(r, c + 1) == first do c = c + 1 end
        out[#out + 1] = { attr = first, bg_end = c }
      end
      return out
    ]])
    assert.are.same(panel[1], panel[2])
    assert.are.same(panel[1], panel[3])
    assert.equals(edge(rows[2], "┤"), panel[1].bg_end)
  end)

  it("keeps table rules aligned when keys scroll a nowrap window without a forced redraw", function()
    ui.exec("vim.wo.wrap = false")
    open({
      "intro paragraph long enough to scroll right by twenty columns", "",
      "| Name | Value |", "| --- | --- |",
      "| alpha | one two three four five six seven eight nine ten |",
      "", "---",
    }, { view = { gutter = 2, max_width = 0 } })
    ui.lines()
    ui.request("nvim_input", "20zl")
    vim.wait(300)
    assert.equals(20, ui.exec("return vim.fn.winsaveview().leftcol"))
    -- read the composed screen as the scroll left it, without a forced redraw
    local rows = ui.exec([[
      local out = {}
      for r = 1, 9 do
        local cells = {}
        for c = 1, 60 do cells[#cells + 1] = vim.fn.screenstring(r, c) end
        out[r] = table.concat(cells):gsub("%s+$", "")
      end
      return out
    ]])
    local function edge(line, char)
      return vim.fn.strdisplaywidth(line:sub(1, line:find(char, 1, true) - 1)) + 1
    end
    assert.equals(edge(rows[5], "┤"), edge(rows[3], "┐"))
    assert.equals(edge(rows[5], "┤"), edge(rows[7], "┘"))
    -- the window-column rule is trimmed by the scroll instead of scrolling natively
    assert.equals(("─"):rep(60 - 20), rows[9])
  end)

  it("keeps code backgrounds inside the reading column in both themes", function()
    for _, colors in ipairs({{0xf0f0f0,0x181818,0x262626},{0x141414,0xfcfcfc,0xededed}}) do
      ui.exec([[
        local c=...
        vim.api.nvim_set_hl(0,'Normal',{fg=c[1],bg=c[2]})
        vim.api.nvim_set_hl(0,'CursorLine',{bg=c[3]})
      ]], {colors})
      open({'```','code','```'})
      assert.equals(string.rep(' ',22)..'code',ui.lines()[2])
      local attrs=ui.exec([[return {
        vim.fn.screenattr(2,1),vim.fn.screenattr(2,21),
        vim.fn.screenattr(2,23),vim.fn.screenattr(2,40),vim.fn.screenattr(2,41)}]])
      assert.are_not.equals(attrs[1],attrs[2])
      assert.are_not.equals(attrs[1],attrs[3])
      assert.equals(attrs[2],attrs[4])
      assert.are_not.equals(attrs[2],attrs[5])
    end
  end)

  it("shades a fence's padding row to the same width as the panel's content", function()
    -- A fence row draws no text, but native wrapping still counts its concealed
    -- source, so the inline fill must stop short by exactly those cells. Left
    -- uncovered, the padding rows end `#fence` cells before the content row and
    -- the panel shows a notch down its right edge. The label makes the two
    -- fences differ in width, so a single shared constant cannot pass this.
    open({ '```lua', 'code', '```' })
    -- Rows 1 and 3 are the panel's padding rows, row 2 carries the content.
    local edges = ui.exec([[
      local out = {}
      for _, row in ipairs({ 1, 2, 3 }) do
        local panel = vim.fn.screenattr(row, 21)
        local last = 0
        for col = 1, vim.o.columns do
          if vim.fn.screenattr(row, col) == panel then last = col end
        end
        out[#out + 1] = last
      end
      return out
    ]])
    assert.equals(edges[2], edges[1])
    assert.equals(edges[2], edges[3])
  end)

  --- Last screen column on `row` painted with the attribute at `col`.
  local RIGHT_EDGE = [[
    local row, col = ...
    local want = vim.fn.screenattr(row, col)
    local last = 0
    for c = 1, vim.o.columns do
      if vim.fn.screenattr(row, c) == want then last = c end
    end
    return last
  ]]

  it("keeps a fence wider than the panel from shading past it", function()
    -- `edge` clamps to the panel's left when the delimiter outgrows the panel,
    -- so an unclamped fill would run the overflow into the margin instead.
    -- Sample inside the panel: column 1 is page background, which reaches the
    -- window edge on every row and would compare equal for the wrong reason.
    open({ '```typescript-with-a-very-long-info-string', 'x = 1', '```' })
    -- Row 1 is the opening fence's padding row, row 3 carries the content.
    local fence = ui.exec(RIGHT_EDGE, { 1, 21 })
    local content = ui.exec(RIGHT_EDGE, { 3, 21 })
    assert.equals(content, fence)
  end)

  it("keeps a label wider than the panel inside it", function()
    -- The caption is drawn over the panel from a window column: inline text
    -- would cost native columns the fence row already owes to its concealed
    -- source, and an untruncated one would paint past the panel's right edge.
    for _, position in ipairs({ 'left', 'right' }) do
      open({ '```typescriptreactwithaverylonglanguagename', 'x = 1', '```' }, {
        render = { code = { label = position } },
      })
      local content = ui.exec(RIGHT_EDGE, { 3, 21 })
      -- The caption's own glyphs must not reach past where the panel ends.
      local caption = ui.exec([[
        local last = 0
        for c = 1, vim.o.columns do
          if vim.fn.screenstring(1, c):match('%S') then last = c end
        end
        return last
      ]])
      assert.is_true(caption > 0)
      assert.is_true(caption <= content)
      -- The content still sits one row below the caption; a label that wrapped
      -- the fence row would push an unshaded row in between.
      assert.equals('                      x = 1', ui.lines()[3])
    end
  end)

  it("measures a tabbed fence row from the column it starts at", function()
    -- A tab's width depends on the column it begins in, so measuring an
    -- indented fence's concealed source from column zero under-counts it and
    -- the panel fill is sized wrong. Asserted on the flow rather than the
    -- screen: the embedded UI renders both widths identically, so only the
    -- measurement itself distinguishes them.
    local h = require("tests.helpers")
    local buf, ctx = h.buffer_with({ "- item", "", "  ```lua\tfoo=1", "  print(1)", "  ```" })
    vim.bo[buf].tabstop = 8
    vim.bo[buf].expandtab = false
    local element = require("preview.render.code")
    local match = require("preview.render.query").matches(buf, { element }, 0, 4).code[1]
    local _, flows = element.render(ctx, match)
    local fence = flows[1]
    assert.is_true(fence.fence)
    -- "  ```lua\tfoo=1" starting at column 2: the tab runs to the next stop at
    -- 8, so the concealed text spans 19 cells, not the 13 a column-zero
    -- measurement reports.
    assert.equals(
      vim.fn.strdisplaywidth("```lua\tfoo=1", 2),
      fence.source_width
    )
  end)

  it("hangs ordered and task continuations under their rendered text", function()
    open({'12. one two three four five six','- [x] one two three four five six'}, {
      view={center=false,max_width=20}, render={checkbox={checked='C',unchecked='U'}},
    })
    local rows=ui.lines()
    assert.equals('12. one two three', rows[1])
    assert.equals('    four five six', rows[2])
    -- The ordered and task lists are two blocks, so the rhythm sets them apart.
    assert.equals('', rows[3])
    assert.equals('C one two three four', rows[4])
    assert.equals('  five six', rows[5])
  end)

  it("keeps wide and combining characters aligned and repeats quote prefixes", function()
    open({string.rep("é界é", 6), "> one two three four five six seven"})
    local rows = ui.lines()
    assert.equals(string.rep(" ",20)..string.rep("é界é",5), rows[1])
    assert.equals(string.rep(" ",20).."é界é", rows[2])
    -- The paragraph and the quote are two blocks, so the rhythm sets them apart.
    assert.equals('', rows[3])
    assert.equals(string.rep(" ",20).."▎ one two three four", rows[4])
    assert.equals(string.rep(" ",20).."▎ five six seven", rows[5])
  end)

  it("bounds long table labels, retains empty fields and preserves quote containers", function()
    ui.resize(40,24)
    local source={'| A long header | B |','| --- | --- |','| | x |','| y |','',
      '> | A | B |','> | --- | --- |','> | one | two |'}
    open(source,{view={max_width=10,gutter=0}})
    local rows=ui.lines()
    assert.equals(string.rep(' ',15)..'A long hea',rows[5])
    assert.equals(string.rep(' ',15)..'der:',rows[6])
    assert.equals(string.rep(' ',15)..'B: x',rows[7])
    assert.truthy(table.concat(rows,'\n'):find('▎ A: one',1,true))
    assert.truthy(table.concat(rows,'\n'):find('▎ B: two',1,true))
    assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it("renders the reference-shaped fixture consistently in dark and light palettes", function()
    ui.resize(120,55)
    local source=vim.fn.readfile('tests/fixtures/reading-view.md')
    local previous
    for _, palette in ipairs({{0xf0f0f0,0x181818,0x262626},{0x141414,0xfcfcfc,0xededed}}) do
      ui.exec([[
        local p=...
        vim.api.nvim_set_hl(0,'Normal',{fg=p[1],bg=p[2]})
        vim.api.nvim_set_hl(0,'CursorLine',{bg=p[3]})
      ]],{palette})
      open(source,{view={max_width=100,gutter=4}})
      local rows=ui.lines()
      assert.equals(string.rep(' ',10)..'Study sheet — project review',rows[1])
      assert.equals(string.rep(' ',12)..'when       Friday, 12:00–12:30',rows[4])
      assert.truthy(table.concat(rows,'\n'):find('• Explain the decision.',1,true))
      assert.truthy(table.concat(rows,'\n'):find('│ Editing │ Changes apply directly',1,true))
      local heading=ui.exec("return vim.api.nvim_get_hl(0,{name='PreviewH1',link=false})")
      assert.equals(palette[1],heading.fg)
      assert.is_true(heading.bold)
      if previous then assert.are.same(previous,rows) end
      previous=rows
      assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
    end
  end)

  it("edits and saves source-backed stacked table fields with native undo", function()
    local source={'| Name | Value |','| --- | --- |','| alpha | a very long value in this cell |'}
    open(source)
    assert.truthy(table.concat(ui.lines(),'\n'):find('Name: alpha',1,true))
    ui.exec('vim.api.nvim_win_set_cursor(0,{3,3})')
    ui.request('nvim_input','iX')
    assert.truthy(table.concat(ui.lines(),'\n'):find('Name: aXlpha',1,true))
    ui.request('nvim_input','<Esc>')
    ui.redraw()
    ui.request('nvim_input','u')
    ui.redraw()
    assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
    ui.request('nvim_input','<C-r>')
    ui.redraw()
    local saved=ui.exec([[
      local path=vim.fn.tempname()..'.md'
      vim.cmd.write(path)
      local lines=vim.fn.readfile(path)
      vim.fn.delete(path)
      return lines
    ]])
    assert.equals('| aXlpha | a very long value in this cell |',saved[3])
    assert.truthy(table.concat(ui.lines(),'\n'):find('Name: aXlpha',1,true))
  end)
end)
