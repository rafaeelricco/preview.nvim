---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")

describe("render.rhythm", function()
  local buf, ctx, by_row

  before_each(function()
    buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    by_row = h.marks_for(buf, ctx)
  end)
  after_each(h.wipe)

  --- Rhythm's own gap mark: blank virt_lines with no highlight, distinct from
  --- a fence's own panel-fill virt_lines (non-empty text, PreviewCodeBlock).
  local function is_gap(m)
    return m.opts.virt_lines ~= nil and m.opts.virt_lines_above == true and m.opts.virt_lines[1][1][1] == ""
  end

  --- Rhythm's own blank-row conceal: bare `conceal_lines`, distinct from a
  --- fence delimiter's own mark, which pairs `conceal_lines` with `conceal`.
  local function is_blank_conceal(m)
    return m.opts.conceal_lines ~= nil and m.opts.conceal == nil
  end

  --- Rows the reader actually sees between the block ending at `from` and the
  --- block starting at `to`: the source blanks left alone, plus the virtual
  --- rows added above `to`. Pure.
  ---@param rows table<integer, preview.Mark[]>
  ---@param context preview.Context
  ---@param from integer
  ---@param to integer
  ---@return integer
  local function drawn_gap(rows, context, from, to)
    local count = 0
    for row = from + 1, to - 1 do
      if context.lines(row):match("^%s*$") and #h.find(rows, row, is_blank_conceal) == 0 then
        count = count + 1
      end
    end
    for _, mark in ipairs(h.find(rows, to, is_gap)) do
      count = count + #mark.opts.virt_lines
    end
    return count
  end

  -- render-unit.md: an H1..H6 ladder (rows 0,2,4,6,8,10) nested through six
  -- levels of the grammar's `section` wrapper, then a bare "#" (row 12), a
  -- paragraph (14), a loose list (16-22), a block quote (23-25), three fenced
  -- code blocks (27-29, 31-33, 35-37) and three paragraphs (39, 41, 43-44).

  it("flattens blocks through nested sections in document order", function()
    -- Every heading is nested one `section` deeper than the last, so these
    -- gaps only come out right if `blocks` descends through every level
    -- rather than stopping at document's direct children.
    local expected = { [2] = 1, [4] = 1, [6] = 1, [8] = 1, [10] = 1, [12] = 2 }
    local previous = { [2] = 0, [4] = 2, [6] = 4, [8] = 6, [10] = 8, [12] = 10 }
    for _, row in ipairs({ 2, 4, 6, 8, 10, 12 }) do
      assert.equals(expected[row], drawn_gap(by_row, ctx, previous[row], row), "row " .. row)
    end
  end)

  it("collapses a gap to the max of the two margins, never their sum", function()
    -- H1 -> H2: heading.below[1] = 1, heading.above[2] = 1; the sum would be 2.
    assert.equals(1, drawn_gap(by_row, ctx, 0, 2))
    -- H6 -> the bare "#": heading.below[6] = 1, heading.above[1] = 2.
    assert.equals(2, drawn_gap(by_row, ctx, 10, 12))
  end)

  it("reuses the source's blank rows and hides only the surplus", function()
    -- Four blank rows where the rhythm wants one: three are hidden and the
    -- fourth is left standing, so no virtual row is needed at all.
    local wide, wctx = h.buffer_with({ "para one", "", "", "", "", "para two" })
    local rows = h.marks_for(wide, wctx)
    local hidden = 0
    for row = 1, 4 do hidden = hidden + #h.find(rows, row, is_blank_conceal) end
    assert.equals(3, hidden)
    assert.equals(0, #h.find(rows, 5, is_gap))
    assert.equals(1, drawn_gap(rows, wctx, 0, 5))
  end)

  it("adds virtual rows only where the source is short", function()
    -- One blank row where an H1 wants two: the blank stays and a single
    -- virtual row makes up the difference.
    local tight, tctx = h.buffer_with({ "para", "", "# Heading" })
    local rows = h.marks_for(tight, tctx)
    assert.equals(0, #h.find(rows, 1, is_blank_conceal))
    local gap = h.find(rows, 2, is_gap)
    assert.equals(1, #gap)
    assert.equals(1, #gap[1].opts.virt_lines)
    assert.equals(2, drawn_gap(rows, tctx, 0, 2))
  end)

  it("never hides a row next to one carrying virtual lines", function()
    -- Neovim redraws that pairing incorrectly while scrolling: a wrapped row
    -- is drawn twice. Adjusting the difference is what keeps them apart.
    for _, lines in ipairs({
      h.fixture("render-unit.md"),
      h.fixture("elements.md"),
      { "para", "", "", "", "## Heading", "", "text", "", "", "### Third", "x" },
    }) do
      local probe, pctx = h.buffer_with(lines)
      local rows = h.marks_for(probe, pctx)
      for row = 0, #lines - 1 do
        if #h.find(rows, row, is_blank_conceal) > 0 then
          for _, neighbour in ipairs({ row - 1, row, row + 1 }) do
            assert.equals(0, #h.find(rows, neighbour, is_gap), "hidden row " .. row)
          end
        end
      end
    end
  end)

  it("sizes the gap from the configured spacing, per element kind", function()
    -- Row 16 opens the list, after the paragraph on row 14; both margins are 1
    -- by default. Widening only the list's `above` must win the collapse.
    local wide = h.marks_for(buf, h.with_config(ctx, { spacing = { list = { above = 4, below = 1 } } }))
    assert.equals(4, drawn_gap(wide, ctx, 14, 16))

    -- Zero on both sides hides the source's blank, so the blocks meet.
    local tight = h.marks_for(buf, h.with_config(ctx, {
      spacing = { list = { above = 0, below = 0 }, paragraph = { above = 0, below = 0 } },
    }))
    assert.equals(0, drawn_gap(tight, ctx, 14, 16))
    assert.equals(1, #h.find(tight, 15, is_blank_conceal))
  end)

  it("owns the blank rows a list's range swallows after its last item", function()
    -- The grammar gives the loose list rows 16..23, reaching past its own
    -- trailing blank and into the quote's first row. Left alone, that blank
    -- would count as inside the list and the gap would stack on top of it.
    assert.equals(1, drawn_gap(by_row, ctx, 21, 23))
  end)

  it("leaves blank rows inside a block untouched", function()
    -- Row 19 sits between two loose list items, genuinely inside the `list`.
    assert.equals(0, #h.find(by_row, 19, is_blank_conceal))
    -- Row 36 is the blank line inside the ```sh``` fence: content, not spacing.
    assert.equals(0, #h.find(by_row, 36, is_blank_conceal))
  end)

  it("anchors a gap after a concealed opening fence, never on the fence row", function()
    -- Row 27 is the "```lua" delimiter, concealed by the code element itself,
    -- so a gap mark there would render nothing at all.
    local short, sctx = h.buffer_with({ "# Title", "```lua", "code", "```" })
    local rows = h.marks_for(short, sctx)
    assert.equals(0, #h.find(rows, 1, is_gap))
    local gap = h.find(rows, 2, is_gap)
    assert.equals(1, #gap)
  end)

  it("emits no gap mark when every row of the next block is a fence", function()
    -- An unclosed one-line fence draws nothing, so there is no visible row to
    -- hang a gap above; emitting one would silently vanish.
    local open, octx = h.buffer_with({ "# Title", "```" })
    local rows = h.marks_for(open, octx)
    for row = 0, 1 do assert.equals(0, #h.find(rows, row, is_gap), "row " .. row) end
  end)
end)
