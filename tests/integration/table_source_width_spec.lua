local screen = require('tests.screen')

local SNAPSHOT = [==[## How the draft was challenged

The [initial draft](review/initial-draft.md) was reviewed in three parallel batches, with 72 cases per reviewer. Each batch contains eight cases in each of nine families. Every case records a constraint, a breaking event, relevant questions, the decisive design response, and a gap when applicable. The [complete case record](review/scenarios.json) preserves all 216 cases and their original-draft verdicts.

| Batch                     | System families                                                                                                                             | Covered | Clarify | Specialist |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------: | ------: | ---------: |
| [A](review/reviewer-A.md) | Reservations, payments, identity, healthcare workflows, exchanges, inventory, vendors, human approvals, configuration.                      |      39 |      16 |         17 |
| [B](review/reviewer-B.md) | Search/feeds, chat, storage, offline sync, analytics, queues, caches, multiplayer/geospatial, observability.                                |      40 |      24 |          8 |
| [C](review/reviewer-C.md) | Embedded control, IoT, AI, compilers/builds, local tools, scientific computing, browser interfaces, security, legacy/organizational change. |      32 |      14 |         26 |
| Total                     | 27 families                                                                                                                                 |     111 |      54 |         51 |

“Covered” means the reviewer judged that the wording would plausibly surface the decisive concern. “Clarify” means a learner could answer the broad question and still miss it. “Specialist” means the framework reveals a concern whose policy or proof needs domain expertise. These labels are judgments about prompts, not successful system tests. The counts are not a success rate.]==]
local SOURCE = vim.split(SNAPSHOT, '\n', { plain = true })

local EXPECTED_ROWS = {
  {'Batch', 'System families', 'Covered', 'Clarify', 'Specialist'},
  {'A', 'Reservations, payments, identity, healthcare workflows, exchanges, inventory, vendors, human approvals, configuration.', '39', '16', '17'},
  {'B', 'Search/feeds, chat, storage, offline sync, analytics, queues, caches, multiplayer/geospatial, observability.', '40', '24', '8'},
  {'C', 'Embedded control, IoT, AI, compilers/builds, local tools, scientific computing, browser interfaces, security, legacy/organizational change.', '32', '14', '26'},
  {'Total', '27 families', '111', '54', '51'},
}

local function normalized(rows)
  return table.concat(rows, '\n'):gsub('%s+', ' ')
end

local function positions(line, symbols)
  local result = {}
  for _, symbol in ipairs(symbols) do
    local from = 1
    while true do
      local at = line:find(symbol, from, true)
      if not at then break end
      result[#result + 1] = vim.fn.strdisplaywidth(line:sub(1, at - 1))
      from = at + #symbol
    end
  end
  table.sort(result)
  return result
end

---@param rows string[]
---@return integer, integer, string[]
local function grid_block(rows)
  local first, last
  for index, line in ipairs(rows) do
    if not first and line:find('┌', 1, true) then first = index end
    if first and line:find('└', 1, true) then last = index; break end
  end
  assert(first and last, table.concat(rows, '\n'))
  return first, last, vim.list_slice(rows, first, last)
end

local function grid_cells(grid)
  local columns = #positions(grid[1], {'┌', '┬', '┐'}) - 1
  local function empty_row()
    local row = {}
    for col = 1, columns do row[col] = '' end
    return row
  end
  local result, current = {}, empty_row()
  local function flush()
    result[#result + 1] = current
    current = empty_row()
  end
  for index = 2, #grid - 1 do
    local line = grid[index]
    if line:find('├', 1, true) then
      flush()
    else
      local borders, from = {}, 1
      while true do
        local at = line:find('│', from, true)
        if not at then break end
        borders[#borders + 1] = at
        from = at + #'│'
      end
      assert.are.equal(columns + 1, #borders, line)
      for col = 1, columns do
        local cell = line:sub(borders[col] + #'│', borders[col + 1] - 1):gsub('^ +', ''):gsub(' +$', '')
        if cell ~= '' then
          current[col] = current[col] == '' and cell or (current[col] .. ' ' .. cell)
        end
      end
    end
  end
  flush()
  return result
end

describe('source-native table width regression', function()
  local ui
  before_each(function() ui = screen.new(240, 50) end)
  after_each(function() ui.close() end)

  local function open(source, opts)
    ui.exec([[
      local source, opts = ...
      vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
      vim.bo.filetype = 'markdown'
      require('preview').setup(vim.tbl_deep_extend('force',
        {default_mode='preview', winbar={enabled=false}}, opts))
    ]], { source or SOURCE, opts or {} })
  end

  local function snapshot()
    return ui.exec([[
      local rows = {}
      for row = 1, vim.o.lines do
        local cells = {}
        for col = 1, vim.o.columns do cells[#cells + 1] = vim.fn.screenstring(row, col) end
        rows[#rows + 1] = table.concat(cells):gsub('%s+$', '')
      end
      return rows
    ]])
  end

  local function table_conceal_rows()
    return ui.exec([[
      local rows = {}
      for name, ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:match('^preview.nvim.window.') then
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {details=true})) do
            if mark[4].conceal_lines ~= nil then rows[mark[2] + 1] = true end
          end
        end
      end
      local result = {}
      for row in pairs(rows) do result[#result + 1] = row end
      table.sort(result)
      return result
    ]])
  end

  it('keeps the complete Review snapshot aligned across native and overflow widths', function()
    open()
    local native_240
    local widths = {240, 229, 228, 220, 188, 187, 180, 240}
    for index, width in ipairs(widths) do
      ui.resize(width, 50)
      ui.exec("vim.cmd('normal! gg')")
      local rows = ui.lines()
      local text = normalized(rows)
      assert.truthy(text:find('How the draft was challenged', 1, true), text)
      assert.truthy(text:find('The initial draft was reviewed in three parallel batches, with 72 cases per reviewer.', 1, true), text)
      assert.truthy(text:find('These labels are judgments about prompts, not successful system tests. The counts are not a success rate.', 1, true), text)
      assert.are.same(SOURCE, ui.exec('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'))

      local concealed = table_conceal_rows()
      if width >= 229 then
        assert.are.same({}, concealed, ('width %d concealed source rows'):format(width))
      else
        assert.are.same({5, 6, 7, 8, 9, 10, 11}, concealed, ('width %d did not use the virtual grid'):format(width))
      end

      local first, last, grid = grid_block(rows)
      assert.are.equal('', rows[first - 1], ('width %d needs one blank above the grid'):format(width))
      assert.not_equals('', rows[first - 2], ('width %d has extra space above the grid'):format(width))
      assert.are.equal('', rows[last + 1], ('width %d needs one blank below the grid'):format(width))
      assert.not_equals('', rows[last + 2], ('width %d has extra space below the grid'):format(width))

      local boundary = positions(grid[1], {'┌', '┬', '┐'})
      assert.are.equal(6, #boundary, ('width %d top border has wrong column count: %s'):format(width, grid[1]))
      local grid_width = math.min(184, width - 4)
      assert.are.equal(grid_width, vim.fn.strdisplaywidth(grid[1]) - 2, ('width %d has wrong grid width'):format(width))
      if width >= 188 then assert.are.same({2, 10, 152, 162, 172, 185}, boundary) end
      assert.are.equal(grid_width + 1, boundary[#boundary])
      assert.are.equal(width >= 188 and 11 or 12, #grid, ('width %d has an extra or missing physical row'):format(width))
      local middle_count = 0
      for index = 2, #grid - 1 do
        local line = grid[index]
        if line:find('├', 1, true) then
          middle_count = middle_count + 1
          assert.are.same(boundary, positions(line, {'├', '┼', '┤'}), ('width %d broken rule: %s'):format(width, line))
        else
          assert.are.same(boundary, positions(line, {'│'}), ('width %d broken cell borders: %s'):format(width, line))
          assert.not_equals('', line:gsub('│', ''):gsub('%s+', ''), ('width %d has an empty continuation row'):format(width, line))
        end
      end
      assert.are.equal(4, middle_count, ('width %d has an extra or missing separator'):format(width))
      assert.are.same(boundary, positions(grid[#grid], {'└', '┴', '┘'}), ('width %d bottom border is misaligned'):format(width))
      assert.are.same(EXPECTED_ROWS, grid_cells(grid), ('width %d changed a cell or its column'):format(width))
      if index == 1 then
        native_240 = rows
      elseif index == #widths then
        assert.are.same(native_240, rows, 'returning to width 240 did not restore the original layout')
      end
    end
  end)

  it('counts end-of-line insertions and the margin at exact native width', function()
    local results = ui.exec([[
      local ctx = require('preview.render.context').new(0, vim.api.nvim_get_current_win(), 0, 0,
        require('preview.config').defaults)
      ctx.lines = function() return 'abc' end
      ctx.left, ctx.width, ctx.window_width = 2, 6, 8
      local marks = {{row=0, col=3, opts={virt_text={{'XYZ', 'Normal'}}, virt_text_pos='inline'}}}
      local fits = require('preview.render.layout').source_row_fits
      local results = {fits(ctx, 0, marks)}
      ctx.window_width = 7
      results[#results + 1] = fits(ctx, 0, marks)
      ctx.window_width, ctx.left = 8, 3
      results[#results + 1] = fits(ctx, 0, marks)
      return results
    ]])
    assert.are.same({true, false, false}, results)
  end)

  it('keeps tabbed cells aligned with a nonzero gutter', function()
    local source = {'before', '', '| A | B |', '| --- | --- |', '| abcdefghij | a\tb |', '', 'after'}
    ui.resize(32, 24)
    open(source, {view={gutter=3}})
    ui.exec('vim.bo.tabstop = 8')
    local first, last, grid = grid_block(ui.lines())
    local boundaries = positions(grid[1], {'┌', '┬', '┐'})
    assert.are.equal(3, boundaries[1])
    for index = 2, #grid - 1 do
      assert.are.same(boundaries, positions(grid[index], {'│', '├', '┼', '┤'}))
    end
    assert.are.same(boundaries, positions(grid[#grid], {'└', '┴', '┘'}))
    local cells = grid_cells(grid)
    assert.are.equal('abcdefghij', cells[2][1])
    assert.are.equal('ab', cells[2][2]:gsub('%s+', ''))
    assert.are.equal('', ui.lines()[first - 1])
    assert.are.equal('', ui.lines()[last + 1])
    assert.are.same({3, 4, 5, 6}, table_conceal_rows())
    assert.are.same(source, ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('keeps wrapped-anchor cursor movement and incremental scrolling stable', function()
    open()
    ui.resize(220, 18)
    local seen = {}
    for _, keys in ipairs({'gg', 'j', 'j', '$', 'j', 'j', '<C-e>', '<C-e>', '<C-y>', 'G', 'gg'}) do
      ui.request('nvim_input', keys)
      ui.exec('vim.wait(20)')
      local incremental = snapshot()
      vim.list_extend(seen, incremental)
      ui.redraw()
      assert.are.same(incremental, snapshot(), keys)
    end
    local text = normalized(seen)
    for _, cells in ipairs(EXPECTED_ROWS) do
      for _, cell in ipairs(cells) do assert.truthy(text:find(cell, 1, true), cell) end
    end
    assert.are.same(SOURCE, ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('keeps short-window and table-only source readable and restores the grid', function()
    open()
    ui.resize(220, 12)
    assert.are.same({}, table_conceal_rows())
    local seen = {}
    for _ = 1, 22 do
      vim.list_extend(seen, ui.lines())
      ui.request('nvim_input', '<C-e>')
      ui.exec('vim.wait(10)')
    end
    local text = normalized(seen)
    for _, cells in ipairs(EXPECTED_ROWS) do
      for _, cell in ipairs(cells) do assert.truthy(text:find(cell, 1, true), cell) end
    end
    ui.resize(220, 50)
    ui.exec("vim.cmd('normal! gg')")
    grid_block(ui.lines())
    local source = vim.list_slice(SOURCE, 5, 10)
    open(source)
    assert.are.same({}, table_conceal_rows())
    assert.is_nil(table.concat(ui.lines(), '\n'):find('┌', 1, true))
    local fallback = normalized(ui.lines())
    for _, cells in ipairs(EXPECTED_ROWS) do
      for _, cell in ipairs(cells) do assert.truthy(fallback:find(cell, 1, true), cell) end
    end
    assert.are.same(source, ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)

  it('preserves nowrap rendering and horizontal scrolling', function()
    open(nil, {view={wrap=false}})
    ui.resize(100, 50)
    assert.are.same({}, table_conceal_rows())
    ui.exec("vim.cmd('normal! 7G160zl')")
    local text = table.concat(ui.lines(), '\n')
    assert.truthy(text:find('Specialist', 1, true), text)
    assert.truthy(text:find('┐', 1, true), text)
    assert.is_true(ui.exec('return vim.fn.winsaveview().leftcol > 0'))
    assert.are.same(SOURCE, ui.exec('return vim.api.nvim_buf_get_lines(0,0,-1,false)'))
  end)
end)
