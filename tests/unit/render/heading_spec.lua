---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")

describe("render.heading", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  local function is_line_hl(m)
    return m.opts.hl_group ~= nil
  end

  -- render-unit.md: "# Heading one" .. "###### Heading six" on rows 0,2,..,10; bare "#" on row 12
  local ROWS = { 0, 2, 4, 6, 8, 10 }

  it("conceals the marker plus one trailing space for every level", function()
    for level = 1, 6 do
      local row = ROWS[level]
      local conceals = h.find(by_row, row, h.is_conceal)
      assert.equals(1, #conceals, "row " .. row)
      assert.are.same({ row = row, col = 0, opts = { end_col = level + 1, conceal = "" } }, conceals[1])
    end
  end)

  it("highlights the source text by level and emits no icon by default", function()
    for level = 1, 6 do
      local row = ROWS[level]
      local hl = "PreviewH" .. level
      assert.are.same({ { row = row, col = 0, opts = { end_col = #ctx.lines(row), hl_group = hl } } }, h.find(by_row, row, is_line_hl))
      assert.equals(0, #h.find(by_row, row, h.has_virt("inline")), "row " .. row)
    end
  end)

  it("places an explicit icon inline at col 0", function()
    local icons = { "1", "2", "3", "4", "5", "6" }
    local rows = h.marks_for(buf, h.with_config(ctx, { heading = { icons = icons } }))
    for level = 1, 6 do
      local row = ROWS[level]
      local hl = "PreviewH" .. level
      assert.are.same({
        { row = row, col = 0, opts = { virt_text = { { icons[level] .. " ", hl } }, virt_text_pos = "inline" } },
      }, h.find(rows, row, h.has_virt("inline")), "row " .. row)
    end
  end)

  it("clamps the conceal range on a bare '#'", function()
    local conceals = h.find(by_row, 12, h.is_conceal)
    assert.equals(1, #conceals)
    assert.are.same({ row = 12, col = 0, opts = { end_col = 1, conceal = "" } }, conceals[1])
    assert.are.same({ { row = 12, col = 0, opts = { end_col = 1, hl_group = "PreviewH1" } } }, h.find(by_row, 12, is_line_hl))
  end)
end)
