--- Pure helpers over TSNode values. No Neovim API calls.
local M = {}

--- First direct child whose type is one of `types`, or nil.
---@param node TSNode
---@param types string[]
---@return TSNode|nil
function M.first_child_of_type(node, types)
  local wanted = {}
  for _, t in ipairs(types) do
    wanted[t] = true
  end
  for child in node:iter_children() do
    if wanted[child:type()] then
      return child
    end
  end
  return nil
end

--- Number of ancestors of `node` (excluding itself) whose type is `type`.
---@param node TSNode
---@param type string
---@return integer
function M.count_ancestors(node, type)
  local count = 0
  local parent = node:parent()
  while parent do
    if parent:type() == type then
      count = count + 1
    end
    parent = parent:parent()
  end
  return count
end

return M
