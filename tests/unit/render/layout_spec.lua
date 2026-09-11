local layout = require("preview.render.layout")

describe("reading layout", function()
  local function context(line)
    return {
      buf = 0, win = 0, display_signature = "", tick = 0,
      config = require("preview.config").defaults.render,
      width = 20, window_width = 40, left = 10, leftcol = 0, top = 0, bot = 0,
      view = { wrap = true, max_width = 20, center = true, gutter = 0 },
      tabstop = 4, vartabstop = "", lines = function() return line end,
    }
  end

  it("centers a capped column and clamps margins in tiny windows", function()
    local view = { gutter = 4, wrap = true, max_width = 100, center = true }
    assert.are.same({ 100, 30 }, { layout.geometry(160, view) })
    assert.are.same({ 52, 4 }, { layout.geometry(60, view) })
    assert.are.same({ 1, 0 }, { layout.geometry(1, view) })
    view.center = false
    assert.are.same({ 100, 4 }, { layout.geometry(160, view) })
    view.max_width = 0
    assert.are.same({ 152, 4 }, { layout.geometry(160, view) })
    view.wrap = false
    assert.are.same({ 156, 4 }, { layout.geometry(160, view) })
  end)

  it("scrolls virtual lines natively and trims window-column marks in a nowrap window", function()
    local ctx = context("| a |")
    ctx.view.wrap, ctx.left, ctx.leftcol = false, 0, 3
    local marks = {
      { row = 0, col = 0, opts = { virt_lines = { { { "┌─────┐", "PreviewTable" } } }, virt_lines_above = true } },
      { row = 0, col = 0, opts = { virt_text = { { "label", "PreviewCodeLabel" } }, virt_text_win_col = 2 } },
      { row = 0, col = 0, opts = { virt_lines = { { { "", "PreviewH1" } } }, virt_lines_above = true } },
    }
    local out = layout.apply(ctx, { [0] = marks }, {})[0]
    assert.are.same({ { "┌─────┐", "PreviewTable" } }, out[1].opts.virt_lines[1])
    assert.equals("scroll", out[1].opts.virt_lines_overflow)
    assert.equals(0, out[2].opts.virt_text_win_col)
    assert.are.same({ { "abel", "PreviewCodeLabel" } }, out[2].opts.virt_text)
    assert.are.same({ { "", "PreviewH1" } }, out[3].opts.virt_lines[1])
    assert.equals("scroll", out[3].opts.virt_lines_overflow)
  end)

  it("measures conceal replacements and icons once without mutating marks", function()
    local ctx = context("**bold** `x`")
    local marks = {
      { row = 0, col = 0, opts = { end_col = 2, conceal = "" } },
      { row = 0, col = 0, opts = { end_col = 1, conceal = "" } },
      { row = 0, col = 6, opts = { end_col = 8, conceal = "" } },
      { row = 0, col = 9, opts = { end_col = 10, conceal = " " } },
      { row = 0, col = 11, opts = { end_col = 12, conceal = " " } },
    }
    local copy = vim.deepcopy(marks)
    local width, text = layout.measure(ctx, 0, 0, 12, marks)
    assert.equals("bold  x ", text)
    assert.equals(8, width)
    assert.are.same(copy, marks)
    width, text = layout.measure(context("[x] item"), 0, 0, 8, {
      { row = 0, col = 0, opts = { end_col = 3, conceal = "", virt_text = {{"✓", "Normal"}}, virt_text_pos = "inline" } },
    })
    assert.equals("✓ item", text)
    assert.equals(6, width)
  end)

  it("measures display cells, combining characters and tab stops", function()
    local text = "é界é\tx"
    local width = layout.measure(context(text), 0, 0, #text, {})
    assert.equals(9, width)
  end)
end)
