local h = require("tests.helpers")

describe("render.code", function()
  after_each(h.wipe)

  local function render(lines, options)
    local buf, ctx = h.buffer_with(lines)
    if options then ctx = h.with_config(ctx, { code = options }) end
    local element = require("preview.render.code")
    local match = require("preview.render.query").matches(buf, {element}, 0, #lines - 1).code[1]
    return element.render(ctx, match)
  end

  it("keeps source content editable and shades only source ranges", function()
    local marks, flows = render({'```lua', 'print("hi")', '```'})
    assert.equals(3, #flows)
    for row = 0, 2 do
      assert.equals(row, flows[row + 1].row)
      assert.equals("code", flows[row + 1].kind)
      assert.equals(2, flows[row + 1].padding)
      assert.equals("PreviewCodeBlock", flows[row + 1].background)
    end
    assert.is_true(flows[1].fence)
    assert.is_nil(flows[2].fence)
    assert.is_true(flows[3].fence)
    local highlights, conceals = 0, 0
    for _, mark in ipairs(marks) do
      -- No element may remove a row with `conceal_lines`: Neovim redraws a
      -- hidden row that neighbours a `virt_lines` row incorrectly while
      -- scrolling. A fence conceals its text and keeps the row.
      assert.is_nil(mark.opts.conceal_lines)
      assert.is_nil(mark.opts.line_hl_group)
      if mark.opts.hl_group == "PreviewCodeBlock" then highlights = highlights + 1 end
      if mark.opts.conceal ~= nil then conceals = conceals + 1 end
    end
    assert.equals(3, highlights)
    assert.equals(2, conceals)
    assert.is_nil(flows[1].label)
  end)

  it("passes labels to panel-relative layout without hiding content", function()
    for _, position in ipairs({'left', 'right'}) do
      local _, flows = render({'```lua', 'code', '```'}, {label=position,padding=3})
      assert.equals('lua', flows[1].label)
      assert.equals(position, flows[1].label_position)
      assert.equals(3, flows[2].padding)
      assert.is_nil(flows[2].label)
      assert.is_nil(flows[3].label)
    end
    local _, plain = render({'```', 'text', '```'}, {label='right'})
    assert.is_nil(plain[1].label)
  end)

  it("preserves container prefixes on code fences", function()
    local marks, flows = render({'> ```lua', '> code', '> ```'})
    assert.equals(2, flows[1].start_col)
    for _, mark in ipairs(marks) do
      if not mark.opts.virt_lines then assert.equals(2, mark.col) end
    end
  end)
end)
