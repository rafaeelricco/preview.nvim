---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")

describe("render.list", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  --- Row flows for a context, via the same collect path h.marks_for uses but
  --- keeping the second return value h.marks_for discards.
  ---@param c preview.Context
  ---@return table<integer, preview.RowFlow>
  local function flows_for(c)
    local render = require("preview.render")
    local elems = render.elements()
    local _, flows = render.collect(c, elems, require("preview.render.query").matches(buf, elems, c.top, c.bot))
    return flows
  end

  it("inserts a bullet chosen by depth on each marker", function()
    -- rows 16..18: "- top level", "  - second level", "    - third level"
    local expected = { { 16, 0, 1 }, { 17, 2, 2 }, { 18, 4, 3 } }
    for _, e in ipairs(expected) do
      local row, col, depth = e[1], e[2], e[3]
      local overlays = h.find(by_row, row, h.has_virt("inline"))
      assert.equals(1, #overlays, "row " .. row)
      assert.are.same({
        row = row,
        col = col,
        opts = {
          end_col = col + 2, -- swallows the marker's own trailing space too
          conceal = "",
          virt_text = { { ctx.config.list.bullets[depth] .. " ", "PreviewBullet" } },
          virt_text_pos = "inline",
        },
      }, overlays[1])
    end
  end)

  it("wraps around the bullet list when deeper than the configured bullets", function()
    local narrow = h.with_config(ctx, { list = { bullets = { "x", "y" } } })
    local rows = h.marks_for(buf, narrow)
    local third = h.find(rows, 18, h.has_virt("inline"))
    assert.equals("x ", h.virt_string(third[1]))
  end)

  it("widens the bullet's emitted gap and continuation indent with render.list.gap", function()
    local base_flows = flows_for(ctx)
    for _, gap in ipairs({ 2, 0 }) do
      local wide = h.with_config(ctx, { list = { gap = gap } })
      local rows, flows = h.marks_for(buf, wide), flows_for(wide)
      local overlay = h.find(rows, 16, h.has_virt("inline"))[1]
      assert.are.same({ { "•" .. (" "):rep(gap), "PreviewBullet" } }, overlay.opts.virt_text)
      assert.equals(base_flows[16].indent + (gap - ctx.config.list.gap), flows[16].indent)
    end
  end)

  it("conceals the bullet and replaces the checkbox with an inline icon", function()
    -- row 20: "- [x] done task", row 21: "- [ ] open task"
    for _, e in ipairs({ { 20, ctx.config.checkbox.checked }, { 21, ctx.config.checkbox.unchecked } }) do
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
        opts = { end_col = 6, conceal = "", virt_text = { { icon .. " ", "PreviewCheckbox" } }, virt_text_pos = "inline" }, -- swallows the mandatory space after "]" too
      }, overlays[1])
    end
  end)

  it("widens the checkbox's emitted gap and continuation indent with render.checkbox.gap", function()
    local base_flows = flows_for(ctx)
    for _, gap in ipairs({ 2, 0 }) do
      local wide = h.with_config(ctx, { checkbox = { gap = gap } })
      local rows, flows = h.marks_for(buf, wide), flows_for(wide)
      local overlay = h.find(rows, 20, h.has_virt("inline"))[1]
      assert.are.same({ { ctx.config.checkbox.checked .. (" "):rep(gap), "PreviewCheckbox" } }, overlay.opts.virt_text)
      assert.equals(base_flows[20].indent + (gap - ctx.config.checkbox.gap), flows[20].indent)
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
