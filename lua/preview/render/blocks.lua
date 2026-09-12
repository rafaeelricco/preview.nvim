---@type table<string, preview.BlockKind>
local KIND = {
  atx_heading = "heading", paragraph = "paragraph", list = "list",
  block_quote = "quote", fenced_code_block = "code", indented_code_block = "code",
  pipe_table = "table", thematic_break = "rule",
}

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

local M = {}

--- Document-order blocks, descending through the grammar's nested `section`
--- wrappers so headings and their following blocks stay siblings. Pure.
---@param root TSNode
---@param line fun(row: integer): string
---@return preview.Block[]
function M.of(root, line)
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

return M
