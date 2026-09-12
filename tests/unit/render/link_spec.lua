---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")

describe("render.link", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  -- row 41: "A [one line](https://example.com) link."
  it("conceals the brackets and destination and highlights the text", function()
    local conceals = h.find(by_row, 41, h.is_conceal)
    table.sort(conceals, function(a, b)
      return a.col < b.col
    end)
    assert.are.same({
      { row = 41, col = 2, opts = { end_col = 3, conceal = "" } },
      { row = 41, col = 11, opts = { end_col = 33, conceal = "" } },
    }, conceals)
    assert.are.same(
      { { row = 41, col = 3, opts = { end_col = 11, hl_group = "PreviewLink" } } },
      h.find(by_row, 41, h.has_hl("PreviewLink"))
    )
  end)

  it("emits no icon by default", function()
    assert.equals(0, #h.find(by_row, 41, h.has_virt("inline")))
  end)

  it("puts an explicit icon inline before the text", function()
    local rows = h.marks_for(buf, h.with_config(ctx, { link = { icon = "x" } }))
    assert.are.same({
      { row = 41, col = 3, opts = { virt_text = { { "x ", "PreviewLink" } }, virt_text_pos = "inline" } },
    }, h.find(rows, 41, h.has_virt("inline")))
  end)

  it("widens the icon's emitted gap with render.link.gap", function()
    for _, gap in ipairs({ 2, 0 }) do
      local rows = h.marks_for(buf, h.with_config(ctx, { link = { icon = "x", gap = gap } }))
      assert.are.same({
        { row = 41, col = 3, opts = { virt_text = { { "x" .. (" "):rep(gap), "PreviewLink" } }, virt_text_pos = "inline" } },
      }, h.find(rows, 41, h.has_virt("inline")))
    end
  end)

  it("renders a link whose text spans two lines raw", function()
    -- rows 43..44: "A [two" / "line](https://example.com) link."
    -- No link marks land here; row 43 may still carry an unrelated rhythm gap.
    for _, row in ipairs({ 43, 44 }) do
      assert.equals(0, #h.find(by_row, row, h.is_conceal), "row " .. row)
      assert.equals(0, #h.find(by_row, row, h.has_hl("PreviewLink")), "row " .. row)
      assert.equals(0, #h.find(by_row, row, h.has_virt("inline")), "row " .. row)
    end
  end)
end)
