---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")

describe("render.list", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  it("inserts a bullet chosen by depth on each marker", function()
    -- rows 10..12: "- top level", "  - second level", "    - third level"
    local expected = { { 10, 0, 1 }, { 11, 2, 2 }, { 12, 4, 3 } }
    for _, e in ipairs(expected) do
      local row, col, depth = e[1], e[2], e[3]
      local overlays = h.find(by_row, row, h.has_virt("inline"))
      assert.equals(1, #overlays, "row " .. row)
      assert.are.same({
        row = row,
        col = col,
        opts = { end_col = col + 1, conceal = "", virt_text = { { ctx.config.list.bullets[depth], "PreviewBullet" } }, virt_text_pos = "inline" },
      }, overlays[1])
    end
  end)

  it("wraps around the bullet list when deeper than the configured bullets", function()
    local narrow = h.with_config(ctx, { list = { bullets = { "x", "y" } } })
    local rows = h.marks_for(buf, narrow)
    local third = h.find(rows, 12, h.has_virt("inline"))
    assert.equals("x", h.virt_string(third[1]))
  end)

  it("conceals the bullet and replaces the checkbox with an inline icon", function()
    -- row 14: "- [x] done task", row 15: "- [ ] open task"
    for _, e in ipairs({ { 14, ctx.config.checkbox.checked }, { 15, ctx.config.checkbox.unchecked } }) do
      local row, icon = e[1], e[2]
      local conceals = h.find(by_row, row, function(mark)
        return h.is_conceal(mark) and mark.col == 0
      end)
      assert.equals(1, #conceals, "row " .. row)
      assert.are.same({ row = row, col = 0, opts = { end_col = 2, conceal = "" } }, conceals[1])

      local overlays = h.find(by_row, row, h.has_virt("inline"))
      assert.equals(1, #overlays, "row " .. row)
      assert.are.same({
        row = row,
        col = 2,
        opts = { end_col = 5, conceal = "", virt_text = { { icon, "PreviewCheckbox" } }, virt_text_pos = "inline" },
      }, overlays[1])
    end
  end)

  it("keeps ordered numbers as highlighted editable source", function()
    local obuf, octx = h.buffer_with({ "1. first", "2. second" })
    local rows = h.marks_for(obuf, octx)
    for row = 0, 1 do
      assert.equals(1, #h.find(rows, row, h.has_hl("PreviewBullet")))
      assert.equals(0, #h.find(rows, row, h.is_conceal))
    end
  end)
end)
