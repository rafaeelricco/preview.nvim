local h = require("tests.helpers")

describe("render.emphasis", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  -- row 8: "Some **bold** and *italic* words."
  it("highlights strong emphasis and conceals each delimiter character", function()
    local hl = h.find(by_row, 8, h.has_hl("PreviewBold"))
    assert.equals(1, #hl)
    assert.are.same({ row = 8, col = 5, opts = { end_row = 8, end_col = 13, hl_group = "PreviewBold" } }, hl[1])

    local conceals = h.find(by_row, 8, function(m)
      return h.is_conceal(m) and m.col >= 5 and m.col < 13
    end)
    table.sort(conceals, function(a, b)
      return a.col < b.col
    end)
    assert.are.same({
      { row = 8, col = 5, opts = { end_col = 6, conceal = "" } },
      { row = 8, col = 6, opts = { end_col = 7, conceal = "" } },
      { row = 8, col = 11, opts = { end_col = 12, conceal = "" } },
      { row = 8, col = 12, opts = { end_col = 13, conceal = "" } },
    }, conceals)
  end)

  it("highlights emphasis and conceals both delimiters", function()
    local hl = h.find(by_row, 8, h.has_hl("PreviewItalic"))
    assert.equals(1, #hl)
    assert.are.same({ row = 8, col = 18, opts = { end_row = 8, end_col = 26, hl_group = "PreviewItalic" } }, hl[1])

    local conceals = h.find(by_row, 8, function(m)
      return h.is_conceal(m) and m.col >= 18
    end)
    table.sort(conceals, function(a, b)
      return a.col < b.col
    end)
    assert.are.same({
      { row = 8, col = 18, opts = { end_col = 19, conceal = "" } },
      { row = 8, col = 25, opts = { end_col = 26, conceal = "" } },
    }, conceals)
  end)
end)
