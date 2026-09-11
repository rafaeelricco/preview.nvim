local h = require('tests.helpers')

describe('editable tables', function()
  after_each(h.wipe)

  local function collect(lines, width, wrap)
    local buf, ctx = h.buffer_with(lines)
    ctx.width = width or 80
    ctx.view.wrap = wrap ~= false
    local render = require('preview.render')
    local elems = render.elements()
    local marks, flows = render.collect(ctx, elems,
      require('preview.render.query').matches(buf, elems, 0, #lines - 1))
    return marks, flows, buf
  end

  local function check_source(marks, words)
    for _, row in pairs(marks) do
      for _, mark in ipairs(row) do
        assert.is_nil(mark.opts.conceal_lines)
        for _, chunk in ipairs(mark.opts.virt_text or {}) do
          for _, word in ipairs(words) do assert.is_nil(chunk[1]:find(word, 1, true)) end
        end
        for _, line in ipairs(mark.opts.virt_lines or {}) do
          for _, chunk in ipairs(line) do
            for _, word in ipairs(words) do assert.is_nil(chunk[1]:find(word, 1, true)) end
          end
        end
      end
    end
  end

  it('decorates fitting table cells without copying or hiding source rows', function()
    local lines = {'| Name | Value |', '| --- | --- |', '| alpha | one |'}
    local marks, flows, buf = collect(lines)
    check_source(marks, {'alpha', 'one'})
    assert.is_nil(flows[2].fields)
    assert.equals('table', flows[2].kind)
    assert.are.same(lines, vim.api.nvim_buf_get_lines(buf,0,-1,false))
  end)

  it('keeps every grid row within its drawn width when Neovim wraps by source', function()
    local lines = {'| Name | Value |', '|---|:-:|', '| alpha | a longer value |', 'beta | two'}
    local marks = collect(lines)
    local drawn
    for _, mark in ipairs(marks[0]) do
      if mark.opts.virt_lines_above then drawn = vim.fn.strdisplaywidth(mark.opts.virt_lines[1][1][1]) end
    end
    for row, line in ipairs(lines) do
      local native = vim.fn.strdisplaywidth(line)
      for _, mark in ipairs(marks[row - 1]) do
        if mark.opts.virt_text_pos == 'inline' then
          native = native + vim.fn.strdisplaywidth(mark.opts.virt_text[1][1])
        end
      end
      assert(native <= drawn, ('row %d wraps as %d cells, draws %d'):format(row, native, drawn))
    end
  end)

  it('stacks fields with original byte ranges when natural widths exceed the column', function()
    local lines = {'| Name | Value |', '| --- | --- |', '| alpha | a very long value |'}
    local marks, flows = collect(lines, 20)
    check_source(marks, {'alpha', 'a very long value'})
    local fields = assert(flows[2].fields)
    assert.equals(2, #fields)
    assert.equals('Name', fields[1].label)
    assert.equals('Value', fields[2].label)
    assert.equals('alpha', lines[3]:sub(fields[1].start_col+1, fields[1].end_col))
    assert.equals('a very long value', lines[3]:sub(fields[2].start_col+1, fields[2].end_col))
  end)

  it('keeps empty cells addressable and omits absent trailing cells', function()
    local lines = {'| Name | Value | More |', '| --- | --- | --- |', '| alpha | |', '| beta |'}
    local _, flows = collect(lines, 10)
    assert.equals(2, #flows[2].fields)
    assert.equals(flows[2].fields[2].start_col, flows[2].fields[2].end_col)
    assert.equals(1, #flows[3].fields)
  end)

  it('uses column fallbacks and keeps inline formatting on source', function()
    local _, flows = collect({'| | Value |', '| --- | --- |', '| **alpha** | [one](url) |'}, 10)
    assert.equals('Column 1', flows[2].fields[1].label)
    assert.equals('Value', flows[2].fields[2].label)
  end)

  it('does not stack in nonwrapping mode', function()
    local _, flows = collect({'| Name | Value |', '| --- | --- |', '| alpha | a very long value |'}, 10, false)
    assert.is_nil(flows[2].fields)
  end)
end)
