---@alias preview.BlockKind "heading"|"paragraph"|"list"|"quote"|"code"|"table"|"rule"

---@class preview.Block
---@field kind preview.BlockKind
---@field level integer|nil   -- headings only
---@field srow integer
---@field erow integer
---@field anchor integer|nil  -- first row that draws; nil when every row is concealed

local blocks = require("preview.render.blocks").of

--- The block's margin on one side, reading the per-level list for headings. Pure.
---@param spacing preview.SpacingConfig
---@param block preview.Block
---@param side "above"|"below"
---@return integer
local function margin(spacing, block, side)
  local entry = spacing[block.kind][side]
  if type(entry) == "table" then return entry[block.level or 1] or 0 end
  return entry
end

---@type preview.Element
return {
  name = "rhythm",
  lang = "markdown",
  query = [[ (document) @root ]],
  --- Conceals every blank source row between two blocks and replaces it with
  --- the designed gap: the larger of the previous block's `below` and the next
  --- block's `above`, never their sum.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local blks = blocks(m.root, ctx.lines)
    ---@type preview.Mark[]
    local marks = {}
    for i = 1, #blks - 1 do
      local prev, nxt = blks[i], blks[i + 1]
      ---@type integer[]
      local blanks = {}
      for row = prev.erow + 1, nxt.srow - 1 do
        -- Only blank rows are surplus; anything the grammar left between two
        -- blocks stays visible rather than being hidden with it.
        if ctx.lines(row):match("^%s*$") then
          blanks[#blanks + 1] = row
        end
      end
      local gap = math.max(margin(ctx.config.spacing, prev, "below"), margin(ctx.config.spacing, nxt, "above"))

      -- Reuse the source's own blank rows: hide only the surplus, and add
      -- virtual rows only where the source is short. Adjusting the difference
      -- keeps a hidden row and a row carrying virtual lines from ever meeting,
      -- which Neovim redraws incorrectly while scrolling -- a wrapped row is
      -- drawn twice. It also emits nothing at all in the common case.
      for index = 1, #blanks - gap do
        marks[#marks + 1] = { row = blanks[index], col = 0, opts = { conceal_lines = "" } }
      end
      if #blanks < gap and nxt.anchor then
        ---@type preview.Chunk[][]
        local blank = {}
        for index = 1, gap - #blanks do
          blank[index] = { { "", "" } }
        end
        marks[#marks + 1] = { row = nxt.anchor, col = 0, opts = { virt_lines = blank, virt_lines_above = true } }
      end
    end
    return marks
  end,
}
