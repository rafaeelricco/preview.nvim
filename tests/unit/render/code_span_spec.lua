local h = require("tests.helpers")

describe("render.code_span", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  -- row 31: "Inline `code` here."
  it("highlights the span including its backticks", function()
    local hl = h.find(by_row, 31, function(m)
      return h.has_hl("PreviewCodeInline")(m) and m.opts.conceal == nil
    end)
    assert.are.same({ { row = 31, col = 7, opts = { end_row = 31, end_col = 13, hl_group = "PreviewCodeInline" } } }, hl)
  end)

  it("turns each backtick into one chip-colored space", function()
    local conceals = h.find(by_row, 31, h.is_conceal)
    table.sort(conceals, function(a, b)
      return a.col < b.col
    end)
    assert.are.same({
      { row = 31, col = 7, opts = { end_col = 8, conceal = " ", hl_group = "PreviewCodeInline" } },
      { row = 31, col = 12, opts = { end_col = 13, conceal = " ", hl_group = "PreviewCodeInline" } },
    }, conceals)
  end)
end)
