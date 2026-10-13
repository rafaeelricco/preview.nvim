local screen = require('tests.screen')

describe('responsive table content', function()
  local ui
  local source = {
    'before', '', '| A | B |', '| --- | --- |',
    '| alpha | one two three four five six |', '', 'after',
  }
  before_each(function() ui = screen.new(60, 40) end)
  after_each(function() ui.close() end)

  local function open(lines, opts)
    ui.exec([[
      local lines, opts = ...
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = 'markdown'
      require('preview').setup(vim.tbl_deep_extend('force', {
        default_mode='preview', winbar={enabled=false}, view={gutter=0},
      }, opts or {}))
    ]], {lines, opts or {}})
  end

  local function content()
    return table.concat(ui.lines(), '\n')
  end

  local function source_unchanged(lines)
    assert.are.same(lines, ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end

  it('fits a wrapped grid, stacks below minimum width, and restores the grid', function()
    open(source)
    for _, width in ipairs({60, 20, 13, 12, 8, 60}) do
      ui.resize(math.max(width, 12), 40)
      ui.exec([[
        require('preview').setup({default_mode='preview',winbar={enabled=false},
          view={gutter=0,max_width=...,center=false}})
      ]], {width})
      ui.exec("vim.cmd('normal! gg')")
      local text = content()
      if width >= 13 then
        assert.truthy(text:find('┌', 1, true), text)
      else
        assert.is_nil(text:find('┌', 1, true))
        assert.truthy(text:find('A:', 1, true), text)
        local compact = text:gsub('%s+', '')
        assert.truthy(compact:find('alpha', 1, true), text)
        assert.truthy(compact:find('onetwothreefourfivesix', 1, true), text)
      end
      for _, row in ipairs(ui.lines()) do assert(vim.fn.strdisplaywidth(row) <= width, row) end
      source_unchanged(source)
    end
    assert.are.same({}, ui.exec('return _G.notifications'))
  end)

  it('preserves complete words and the surrounding gaps in the wrapped grid', function()
    open(source)
    ui.resize(20, 40)
    local rows = ui.lines()
    assert.equals('before', rows[1])
    assert.equals('', rows[2])
    assert.equals('┌───────┬──────────┐', rows[3])
    assert.equals('│ A     │ B        │', rows[4])
    assert.equals('├───────┼──────────┤', rows[5])
    assert.equals('│ alpha │ one two  │', rows[6])
    assert.equals('│       │ three    │', rows[7])
    assert.equals('│       │ four     │', rows[8])
    assert.equals('│       │ five six │', rows[9])
    assert.equals('└───────┴──────────┘', rows[10])
    assert.equals('', rows[11])
    assert.equals('after', rows[12])
    source_unchanged(source)
  end)

  it('leaves unsafe table-only source visible without artificial line breaks', function()
    local lines = vim.list_slice(source, 3, 5)
    open(lines)
    ui.resize(12, 40)
    local compact = content():gsub('%s+', '')
    assert.truthy(compact:find('|alpha|onetwothreefourfivesix|', 1, true), content())
    assert.is_nil(content():find('┌', 1, true))
    source_unchanged(lines)
  end)

  it('keeps hidden rows separated from all virtual-line anchors', function()
    open(source)
    ui.resize(20, 40)
    content()
    local violations = ui.exec([=[
      local hidden, virtual, violations = {}, {}, {}
      for name, ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:match('^preview.nvim.window.') then
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {details=true})) do
            local d = mark[4]
            if d.virt_lines then virtual[mark[2]] = true end
          end
        end
      end
      local render = require('preview.render')
      local cfg = require('preview').config()
      local ctx = require('preview.render.context').new(0, vim.api.nvim_get_current_win(), 0, 6, cfg)
      local marks = render.collect(ctx, render.elements(), require('preview.render.query').matches(0, render.elements(), 0, 6))
      for row, list in pairs(marks) do
        for _, mark in ipairs(list) do if mark.opts.conceal_lines ~= nil then hidden[row] = true end end
      end
      for row in pairs(hidden) do
        for neighbor=row-1,row+1 do if virtual[neighbor] then violations[#violations+1]={row,neighbor} end end
      end
      return violations
    ]=])
    assert.are.same({}, violations)
  end)

  it('edits in Markdown mode and reflows the result without changing buffer identity', function()
    open(source)
    ui.resize(20, 40)
    assert.truthy(content():find('┌', 1, true))
    local original = ui.exec('return vim.api.nvim_get_current_buf()')
    ui.exec("require('preview').set_mode(vim.api.nvim_get_current_win(), 'markdown')")
    ui.exec('vim.api.nvim_win_set_cursor(0,{5,2})')
    ui.request('nvim_input', 'iX<Esc>')
    ui.redraw()
    assert.equals('| Xalpha | one two three four five six |', ui.exec('return vim.api.nvim_get_current_line()'))
    ui.request('nvim_input', 'u')
    ui.redraw()
    source_unchanged(source)
    ui.exec("require('preview').set_mode(vim.api.nvim_get_current_win(), 'preview'); vim.cmd('normal! gg')")
    assert.truthy(content():find('┌', 1, true))
    assert.equals(original, ui.exec('return vim.api.nvim_get_current_buf()'))
  end)
end)
