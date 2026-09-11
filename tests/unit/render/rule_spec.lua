local h = require("tests.helpers")

describe("render.rule", function()
  after_each(h.wipe)

  local function is_rule(m)
    return m.opts.virt_text ~= nil and m.opts.virt_text[1][2] == "PreviewRule"
  end

  it("hides '---' and draws a line across the text width", function()
    local buf, ctx = h.buffer_with({ "above", "", "---", "", "below" })
    local by_row = h.marks_for(buf, ctx)
    assert.are.same({ { row = 2, col = 0, opts = { end_col = 3, conceal = "" } } }, h.find(by_row, 2, h.is_conceal))
    local rules = h.find(by_row, 2, is_rule)
    assert.equals(1, #rules)
    assert.equals("overlay", rules[1].opts.virt_text_pos)
    assert.equals(("─"):rep(ctx.width), h.virt_string(rules[1]))
    assert.equals(ctx.width, vim.fn.strdisplaywidth(h.virt_string(rules[1])))
  end)

  it("matches '***' as well", function()
    local buf, ctx = h.buffer_with({ "", "***", "" })
    local by_row = h.marks_for(buf, ctx)
    assert.equals(1, #h.find(by_row, 1, is_rule))
    assert.are.same({ { row = 1, col = 0, opts = { end_col = 3, conceal = "" } } }, h.find(by_row, 1, h.is_conceal))
  end)

  it("leaves a list marker line alone", function()
    local buf, ctx = h.buffer_with({ "- item", "- other" })
    local by_row = h.marks_for(buf, ctx)
    assert.equals(0, #h.find(by_row, 0, is_rule))
    assert.equals(0, #h.find(by_row, 1, is_rule))
  end)
end)
