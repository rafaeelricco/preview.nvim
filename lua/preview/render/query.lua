local log = require("preview.log")

local M = {}

---@type table<string, vim.treesitter.Query>
local compiled = {}

---@type table<integer, true>  -- buffers that already warned about a missing parser
local warned = {}

--- Compiles `element.query` once per element name. Memoised.
---@param element preview.Element
---@return vim.treesitter.Query
function M.for_element(element)
  local query = compiled[element.name]
  if not query then
    query = vim.treesitter.query.parse(element.lang, element.query)
    compiled[element.name] = query
  end
  return query
end

--- Runs one element's query over one tree, appending matches to `out`.
---@param element preview.Element
---@param root TSNode
---@param buf integer
---@param top integer
---@param bot integer
---@param out preview.Match[]
local function run(element, root, buf, top, bot, out)
  local query = M.for_element(element)
  for _, match in query:iter_matches(root, buf, top, bot + 1, { all = true }) do
    ---@type table<string, TSNode[]>
    local captures = {}
    for id, nodes in pairs(match) do
      captures[query.captures[id]] = nodes
    end
    local root_nodes = captures.root
    if root_nodes and root_nodes[1] then
      out[#out + 1] = { root = root_nodes[1], captures = captures }
    end
  end
end

--- Runs every element's query over the parser's trees for rows [top, bot].
--- Block-grammar elements run on the root tree; inline elements on each
--- markdown_inline child tree. Returns matches grouped by element name.
--- Returns {} (and warns once per buffer) when no parser or parse returns nil.
---@param buf integer
---@param elements preview.Element[]
---@param top integer  0-based inclusive
---@param bot integer  0-based inclusive
---@return table<string, preview.Match[]>
function M.matches(buf, elements, top, bot)
  local parser, err = vim.treesitter.get_parser(buf, "markdown")
  if not parser then
    if not warned[buf] then
      warned[buf] = true
      log.warn_once("render", ("no markdown parser for buffer %d: %s"):format(buf, tostring(err)))
    end
    return {}
  end
  if not parser:parse({ top, bot + 1 }) then
    return {}
  end

  ---@type table<string, preview.Match[]>
  local grouped = {}
  for _, element in ipairs(elements) do
    grouped[element.name] = {}
  end

  parser:for_each_tree(function(tree, ltree)
    local lang = ltree:lang()
    local root = tree:root()
    local srow, _, erow = root:range()
    if erow < top or srow > bot then
      return
    end
    for _, element in ipairs(elements) do
      if element.lang == lang then
        run(element, root, buf, top, bot, grouped[element.name])
      end
    end
  end)
  return grouped
end

return M
