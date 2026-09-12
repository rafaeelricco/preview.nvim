local h = require("tests.helpers")

describe("render.quote", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  local function bar_at(row, col)
    return { row = row, col = col, opts = { end_col = col + 1, conceal = "", virt_text = { { ctx.config.quote.bar, "PreviewQuote" } }, virt_text_pos = "inline" } }
  end

  it("inserts the bar on the quote marker", function()
    -- row 23: "> outer quote"
    local inserts = h.find(by_row, 23, h.has_virt("inline"))
    assert.are.same({ bar_at(23, 0) }, inserts)
  end)

  it("inserts a bar on every '>' of a nested quote line", function()
    -- row 25: "> > inner quote" (outer '>' is a block_continuation, inner one a marker)
    local inserts = h.find(by_row, 25, h.has_virt("inline"))
    table.sort(inserts, function(a, b)
      return a.col < b.col
    end)
    assert.are.same({ bar_at(25, 0), bar_at(25, 2) }, inserts)
  end)

  it("adds nothing for continuation lines without '>'", function()
    local lbuf, lctx = h.buffer_with({ "- item", "  continued" })
    local rows = h.marks_for(lbuf, lctx)
    assert.is_nil(rows[1])
  end)
end)
