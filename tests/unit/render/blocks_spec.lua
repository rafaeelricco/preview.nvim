---@diagnostic disable: redundant-parameter
local h = require("tests.helpers")
local blocks = require("preview.render.blocks")

--- Root TSNode of the buffer's markdown parse tree.
---@param buf integer
---@return TSNode
local function root_of(buf)
  local parser = assert(vim.treesitter.get_parser(buf, "markdown"))
  return parser:parse()[1]:root()
end

describe("render.blocks", function()
  after_each(h.wipe)

  it("flattens blocks through nested sections in document order", function()
    -- render-unit.md nests each heading one `section` deeper than the last
    -- (H1..H6 at rows 0,2,4,6,8,10), so this only comes out right if the walk
    -- descends through every level rather than stopping at document's direct
    -- children.
    local buf, ctx = h.buffer_with(h.fixture("render-unit.md"))
    local blks = blocks.of(root_of(buf), ctx.lines)

    local headings = {}
    for _, block in ipairs(blks) do
      if block.kind == "heading" then
        headings[#headings + 1] = { srow = block.srow, level = block.level }
      end
    end
    assert.are.same({
      { srow = 0, level = 1 },
      { srow = 2, level = 2 },
      { srow = 4, level = 3 },
      { srow = 6, level = 4 },
      { srow = 8, level = 5 },
      { srow = 10, level = 6 },
      { srow = 12, level = 1 },
    }, headings)

    -- The paragraph on row 14 follows the bare "#" in document order, proving
    -- the walk returns from six levels of section descent to keep flattening.
    local after = blks[#headings + 1]
    assert.equals("paragraph", after.kind)
    assert.equals(14, after.srow)
  end)

  it("adjusts a block's end row when it lands on column 0 past its start row", function()
    -- A block_quote's grammar range ends at column 0 of the row after its
    -- content; left uncorrected the block would claim a row it never draws.
    -- Row 2 ("> > inner quote") is not blank, which isolates this adjustment
    -- from the trailing-blank trim exercised below.
    local buf, ctx = h.buffer_with({ "> outer quote", ">", "> > inner quote", "", "next para" })
    local blks = blocks.of(root_of(buf), ctx.lines)
    assert.equals("quote", blks[1].kind)
    assert.equals(0, blks[1].srow)
    assert.equals(2, blks[1].erow)
  end)

  it("trims the trailing blank rows a block's range swallows", function()
    -- A list's grammar range reaches past its own trailing blank rows. Two
    -- blank rows follow "- b" here; both belong to the rhythm, not the list.
    local buf, ctx = h.buffer_with({ "- a", "- b", "", "", "next para" })
    local blks = blocks.of(root_of(buf), ctx.lines)
    assert.equals("list", blks[1].kind)
    assert.equals(0, blks[1].srow)
    assert.equals(1, blks[1].erow)
    assert.equals("paragraph", blks[2].kind)
    assert.equals(4, blks[2].srow)
    assert.equals(4, blks[2].erow)
  end)

  it("anchors nil when every row of a block is a fence", function()
    -- An unclosed one-line fence is entirely its own delimiter row, so there
    -- is no visible row left to anchor a gap mark to.
    local buf, ctx = h.buffer_with({ "# Title", "```" })
    local blks = blocks.of(root_of(buf), ctx.lines)
    assert.equals("code", blks[2].kind)
    assert.equals(1, blks[2].srow)
    assert.equals(1, blks[2].erow)
    assert.is_nil(blks[2].anchor)
  end)
end)
