local screen = require('tests.screen')

describe('table overflow safety', function()
  local ui
  before_each(function() ui = screen.new(24, 50) end)
  after_each(function() ui.close() end)

  local function open(lines, opts)
    ui.exec([[
      local lines, opts = ...
      vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
      vim.bo.filetype='markdown'
      require('preview').setup(vim.tbl_deep_extend('force', {
        default_mode='preview', winbar={enabled=false}, view={gutter=0},
      }, opts or {}))
    ]], {lines, opts or {}})
  end

  local function text() return table.concat(ui.lines(), '\n') end

  local function snapshot()
    return ui.exec([[
      local out={}
      for row=1,vim.o.lines-1 do
        local cells={}
        for col=1,vim.o.columns do cells[#cells+1]=vim.fn.screenstring(row,col) end
        out[#out+1]=table.concat(cells):gsub('%s+$','')
      end
      return out
    ]])
  end

  it('preserves inline highlights and Unicode in virtual wrapped cells', function()
    local source={'before','','| A | B |','| --- | --- |',
      '| **bold** | *italic* and `code` plus [label](https://example.com/long/hidden/path) |',
      '| é界 | **[boldlink](https://example.com)** alpha beta gamma delta |','','after'}
    open(source)
    local rendered=text()
    assert.truthy(rendered:find('┌',1,true),rendered)
    for _, value in ipairs({'bold','italic','code','label','é界','boldlink'}) do
      assert.truthy(rendered:find(value,1,true),rendered)
    end
    assert.is_nil(rendered:find('https://',1,true))
    local chunks=ui.exec([=[
      local chunks={}
      for name,ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:match('^preview.nvim.window.') then
          for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
            for _,line in ipairs(mark[4].virt_lines or {}) do vim.list_extend(chunks,line) end
          end
        end
      end
      return vim.inspect(chunks)
    ]=])
    for _, group in ipairs({'PreviewBold','PreviewItalic','PreviewCodeInline','PreviewLink'}) do
      assert.truthy(chunks:find(group,1,true),chunks)
    end
    local combined=ui.exec([=[
      for name,ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:match('^preview.nvim.window.') then
          for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
            for _,line in ipairs(mark[4].virt_lines or {}) do
              for _,part in ipairs(line) do
                local style=vim.inspect(part[2])
                if part[1]:match('%a') and style:find('PreviewBold',1,true) and style:find('PreviewLink',1,true) then return true end
              end
            end
          end
        end
      end
      return false
    ]=])
    assert.is_true(combined)
    assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('keeps every tall-table row reachable and reconsiders vertical resizing', function()
    local source={'before','','| A | B |','| --- | --- |'}
    for i=1,20 do source[#source+1]=('| id%02d | one two three four five |'):format(i) end
    source[#source+1]=''; source[#source+1]='after'
    open(source)
    ui.resize(24,16)
    ui.exec("vim.cmd('normal! gg')")
    assert.is_nil(text():find('┌',1,true))
    local seen={}
    for _=1,110 do
      local rows=snapshot()
      for id in table.concat(rows,'\n'):gmatch('id%d%d') do seen[id]=true end
      ui.request('nvim_input','<C-e>')
      ui.exec('vim.wait(10)')
    end
    for i=1,20 do assert.is_true(seen[('id%02d'):format(i)]) end
    ui.resize(24,180)
    ui.exec("vim.cmd('normal! gg')")
    assert.truthy(text():find('┌',1,true),text())
    ui.resize(24,16)
    ui.exec("vim.cmd('normal! gg')")
    assert.is_nil(text():find('┌',1,true))
  end)

  it('keeps incremental scrolling and cursor anchors equal to a full repaint', function()
    local source={'before','','| A | B |','| --- | --- |',
      '| alpha | one two three four five six |','','after','','last'}
    open(source)
    assert.truthy(text():find('┌',1,true))
    for _, keys in ipairs({'j','j','j','<C-e>','<C-y>','G','gg'}) do
      ui.request('nvim_input',keys)
      ui.exec('vim.wait(20)')
      local incremental=snapshot()
      ui.redraw()
      assert.are.same(incremental,snapshot())
    end
    assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('falls back without hiding boundary, quoted, and adjacent table content', function()
    for _, source in ipairs({
      {'| A | B |','| --- | --- |','| alpha | one two three four five |'},
      {'before','','| A | B |','| --- | --- |','| alpha | one two three four five |'},
      {'before','','> | A | B |','> | --- | --- |','> | alpha | one two three four five |','','after'},
      {'before','','| A | B |','| --- | --- |','| alpha | one two three four five |','',
        '| C | D |','| --- | --- |','| beta | six seven eight nine ten |','','after'},
    }) do
      open(source)
      ui.resize(12,80)
      ui.exec("vim.cmd('normal! gg')")
      local compact=text():gsub('%s+','')
      assert.truthy(compact:find('alpha',1,true),text())
      assert.truthy(compact:find('onetwothreefourfive',1,true),text())
      if source[7] and source[7]:find('| C',1,true) then
        assert.truthy(compact:find('beta',1,true),text())
      end
      assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
    end
  end)

  it('keeps source spacing when a separator contains wrapping whitespace', function()
    for _, gaps in ipairs({{(' '):rep(70), ''}, {'', ('\t'):rep(20)}}) do
      local source={'before',gaps[1],'| A | B |','| --- | --- |',
        '| alpha | one two three four five six |',gaps[2],'after'}
      open(source)
      local rendered=text()
      assert.is_nil(rendered:find('┌',1,true))
      assert.truthy(rendered:gsub('%s+',''):find('onetwothreefourfivesix',1,true),rendered)
      assert.truthy(rendered:find('after',1,true),rendered)
      assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
    end
  end)

  it('preserves tabs, empty fields, and fallback column labels', function()
    local source={'before','','| | B |','| --- | --- |','| | x |',
      '| a\tb | abcdefghijklmnop |','','after'}
    open(source)
    ui.resize(12,80)
    local compact=text():gsub('%s+','')
    assert.truthy(compact:find('Column1:',1,true),text())
    assert.truthy(compact:find('B:x',1,true),text())
    assert.truthy(compact:find('abcdefghijklmnop',1,true),text())
    assert.truthy(compact:find('ab',1,true),text())
    for _, row in ipairs(ui.lines()) do assert(vim.fn.strdisplaywidth(row)<=12,row) end
  end)

  it('fits the same buffer independently in two preview windows', function()
    ui.resize(90,40)
    local source={'before','','| A | B |','| --- | --- |',
      '| alpha | one two three four five six |','','after'}
    open(source)
    ui.exec([[
      _G.wide=vim.api.nvim_get_current_win()
      vim.cmd('vsplit')
      _G.narrow=vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_width(_G.narrow,20)
      require('preview').set_mode(_G.narrow,'preview')
    ]])
    ui.redraw()
    local windows=ui.exec([[
      local out={}
      for _,win in ipairs({_G.narrow,_G.wide}) do
        local info=vim.fn.getwininfo(win)[1]
        local rows={}
        for r=info.winrow,info.winrow+info.height-1 do
          local cells={}
          for c=info.wincol,info.wincol+info.width-1 do cells[#cells+1]=vim.fn.screenstring(r,c) end
          rows[#rows+1]=table.concat(cells):gsub('%s+$','')
        end
        out[#out+1]=table.concat(rows,'\n')
      end
      return out
    ]])
    assert.truthy(windows[1]:find('│ alpha │ one two  │',1,true),windows[1])
    assert.truthy(windows[2]:find('one two three four five six',1,true),windows[2])
    assert.are.same(source,ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('honors border and row separator settings in an overflow grid', function()
    local source={'before','','| A | B |','| --- | --- |',
      '| alpha | one two three four five six |','| beta | seven eight nine ten |','','after'}
    open(source,{render={table={border=false,row_lines=false}}})
    local rendered=text()
    assert.is_nil(rendered:find('┌',1,true))
    assert.is_nil(rendered:find('└',1,true))
    assert.truthy(rendered:find('│ alpha',1,true),rendered)
    assert.truthy(rendered:find('│ beta',1,true),rendered)
    local _, rules=rendered:gsub('├','')
    assert.equals(1,rules)
  end)

  it('retains every cell character at the minimum grid width', function()
    open({'before','','| A | B |','| --- | --- |',
      '| alpha | one two three four five six |','','after'})
    ui.resize(13,80)
    local first,second={},{}
    for _, row in ipairs(ui.lines()) do
      local a,b=row:match('^│ (.-) │ (.-) │$')
      if a then first[#first+1]=a; second[#second+1]=b end
    end
    assert.equals('Aalpha',table.concat(first):gsub('%s+',''))
    assert.equals('Bonetwothreefourfivesix',table.concat(second):gsub('%s+',''))
  end)

  it('retains extra body columns in labeled fields', function()
    open({'before','','| A | B |','| --- | --- |',
      '| alpha | beta | lastvalue |','','after'})
    ui.resize(12,80)
    local compact=text():gsub('%s+','')
    assert.truthy(compact:find('Column3:lastvalue',1,true),text())
  end)
end)
