---@alias preview.BlockKind "heading"|"paragraph"|"list"|"quote"|"code"|"table"|"rule"

---@type table<string, preview.BlockKind>
local KIND = {
  atx_heading = "heading", paragraph = "paragraph", list = "list",
  block_quote = "quote", fenced_code_block = "code", indented_code_block = "code",
  pipe_table = "table", thematic_break = "rule",
}

---@class preview.Block
---@field kind preview.BlockKind
---@field level integer|nil   -- headings only
---@field srow integer
---@field erow integer
---@field anchor integer|nil  -- first row that draws; nil when every row is concealed

--- First row of `node` that is not a concealed fence, or nil. Pure.
---@param node TSNode
---@param srow integer
---@param erow integer
---@return integer|nil
local function anchor_of(node, srow, erow)
  ---@type table<integer, true>
  local fence_rows = {}
  for child in node:iter_children() do
    if child:type() == "fenced_code_block_delimiter" then
      local row = child:range()
      fence_rows[row] = true
    end
  end
  for row = srow, erow do
    if not fence_rows[row] then
      return row
    end
  end
  return nil
end

--- Document-order blocks, descending through the grammar's nested `section`
--- wrappers so headings and their following blocks stay siblings. Pure.
---@param root TSNode
---@param line fun(row: integer): string
---@return preview.Block[]
local function blocks(root, line)
  ---@type preview.Block[]
  local out = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "section" then
        walk(child)
      else
        local srow, _, erow, ecol = child:range()
        if ecol == 0 and erow > srow then erow = erow - 1 end
        -- A list swallows the blank rows that follow it, and may even reach
        -- into the next block's first row. Trailing blanks are between the
        -- blocks, not inside this one, so the rhythm owns them.
        while erow > srow and line(erow):match("^%s*$") do erow = erow - 1 end
        local kind = KIND[child:type()] or "paragraph"
        local level = nil
        if kind == "heading" then
          for marker in child:iter_children() do
            level = tonumber(marker:type():match("^atx_h(%d)_marker$"))
            if level then break end
          end
        end
        out[#out + 1] = { kind = kind, level = level, srow = srow, erow = erow, anchor = anchor_of(child, srow, erow) }
      end
    end
  end
  walk(root)
  return out
end

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
