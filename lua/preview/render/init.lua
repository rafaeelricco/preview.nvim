--- The only render module with side effects: owns the provider namespace and
--- one persistent, window-scoped extmark namespace per preview window.
local state = require("preview.state")
local log = require("preview.log")
local context = require("preview.render.context")
local query = require("preview.render.query")
local layout = require("preview.render.layout")

local M = {}

--- Namespace used only to register the decoration provider.
M.NS = vim.api.nvim_create_namespace("preview.nvim")

---@type preview.Element[]
local elements = require("preview.render.elements")

---@type preview.Config|nil
local config = nil
local config_generation = 0

---@class preview.RenderCache
---@field ns integer
---@field buf integer
---@field tick integer
---@field width integer
---@field display_signature string
---@field config_generation integer

---@type table<integer, preview.RenderCache>  -- window -> last applied full-buffer render
local cache = {}

---@type table<string, true>  -- element names that already warned this session
local failed = {}

local provider_registered = false
local apply_warning_scheduled = false

--- Stores the render config. The generation makes every window refresh once.
---@param cfg preview.Config
function M.configure(cfg)
  config = cfg
  config_generation = config_generation + 1
end

--- The registered elements, in render order.
---@return preview.Element[]
function M.elements()
  return elements
end

--- Pure given its inputs: runs every element over its matches, groups marks by row.
--- A throwing element is skipped for the whole call and warned once per session.
---@param ctx preview.Context
---@param elems preview.Element[]
---@param matches table<string, preview.Match[]>
---@return table<integer, preview.Mark[]>, table<integer, preview.RowFlow>
function M.collect(ctx, elems, matches)
  ---@type table<integer, preview.Mark[]>
  local by_row, row_flows = {}, {}
  local rank = { list = 1, code = 2, table = 3 }
  for _, element in ipairs(elems) do
    ---@type preview.Mark[]
    local produced, produced_flows = {}, {}
    local ok = true
    for _, match in ipairs(matches[element.name] or {}) do
      local success, result, flows = pcall(element.render, ctx, match, by_row)
      if not success then
        ok = false
        if not failed[element.name] then
          failed[element.name] = true
          log.warn_once("render", ("element %q failed and was skipped: %s"):format(element.name, tostring(result)))
        end
        break
      end
      vim.list_extend(produced_flows, flows or {})
      for _, mark in ipairs(result) do
        produced[#produced + 1] = mark
      end
    end
    if ok then
      for _, flow in ipairs(produced_flows) do
        local previous = row_flows[flow.row]
        if not previous or rank[flow.kind] >= rank[previous.kind] then
          row_flows[flow.row] = flow
        end
      end
      for _, mark in ipairs(produced) do
        local list = by_row[mark.row]
        if not list then
          list = {}
          by_row[mark.row] = list
        end
        list[#list + 1] = mark
      end
    end
  end
  return by_row, row_flows
end

---@param values table
---@return integer[]
local function sorted_integer_keys(values)
  local keys = vim.tbl_keys(values)
  table.sort(keys)
  return keys
end

---@param entry preview.RenderCache
local function clear_entry(entry)
  if vim.api.nvim_buf_is_valid(entry.buf) then
    pcall(vim.api.nvim_buf_clear_namespace, entry.buf, entry.ns, 0, -1)
  end
end

--- Clears the marks owned by `win` from their previous buffer and forgets its cache.
--- Idempotent, and safe after the window itself has closed.
---@param win integer
function M.release(win)
  local entry = cache[win]
  if not entry then
    return
  end
  clear_entry(entry)
  cache[win] = nil
end

local function schedule_apply_warning(err)
  if apply_warning_scheduled then
    return
  end
  apply_warning_scheduled = true
  vim.schedule(function()
    log.warn_once("render", "failed to apply preview; source was left visible: " .. tostring(err))
  end)
end

---@param win integer
---@return integer
local function namespace_for(win)
  local entry = cache[win]
  return entry and entry.ns or vim.api.nvim_create_namespace(("preview.nvim.window.%d"):format(win))
end

---@param win integer
---@param buf integer
local function refresh(win, buf)
  local last = math.max(vim.api.nvim_buf_line_count(buf) - 1, 0)
  local ctx = context.new(buf, win, 0, last, config --[[@as preview.Config]])
  local previous = cache[win]
  if
    previous
    and previous.buf == buf
    and previous.tick == ctx.tick
    and previous.width == ctx.window_width
    and previous.display_signature == ctx.display_signature
    and previous.config_generation == config_generation
  then
    return
  end

  local by_row, row_flows = M.collect(ctx, elements, query.matches(buf, elements, 0, last))
  by_row = layout.apply(ctx, by_row, row_flows)
  local ns = namespace_for(win)
  if previous then
    clear_entry(previous)
  end
  vim.api.nvim__ns_set(ns, { wins = { win } })

  cache[win] = {
    ns = ns,
    buf = buf,
    tick = ctx.tick,
    width = ctx.window_width,
    display_signature = ctx.display_signature,
    config_generation = config_generation,
  }

  for _, row in ipairs(sorted_integer_keys(by_row)) do
    for _, mark in ipairs(by_row[row]) do
      vim.api.nvim_buf_set_extmark(buf, ns, mark.row, mark.col,
        vim.tbl_extend("keep", mark.opts, { priority = 200 }))
    end
  end
end

--- Refreshes persistent marks before window layout starts. Invalid, suspended,
--- raw-mode and buffer-mismatched entries lose any marks they previously owned.
local function on_start()
  if not config then
    return false
  end

  local windows = state.snapshot().windows
  local seen = {}
  for _, win in ipairs(sorted_integer_keys(windows)) do
    seen[win] = true
    local entry = windows[win]
    local valid = vim.api.nvim_win_is_valid(win)
    local actual_buf = valid and vim.api.nvim_win_get_buf(win) or nil
    if
      actual_buf == nil
      or entry.mode ~= "preview"
      or entry.suspended
      or entry.buf ~= actual_buf
      or not state.is_attached(actual_buf)
    then
      M.release(win)
    else
      local ok, err = pcall(refresh, win, actual_buf)
      if not ok then
        local ns = namespace_for(win)
        M.release(win)
        pcall(vim.api.nvim_buf_clear_namespace, actual_buf, ns, 0, -1)
        schedule_apply_warning(err)
      end
    end
  end

  for _, win in ipairs(sorted_integer_keys(cache)) do
    if not seen[win] then
      M.release(win)
    end
  end
end

--- Registers the single provider callback once; marks `buf` attached. Idempotent.
---@param buf integer
function M.attach(buf)
  if not provider_registered then
    vim.api.nvim_set_decoration_provider(M.NS, { on_start = on_start })
    provider_registered = true
  end
  state.set_attached(buf, true)
end

--- Clears every window namespace currently owned by `buf`; unmarks it. Idempotent.
---@param buf integer
function M.detach(buf)
  local wins = {}
  for win, entry in pairs(cache) do
    if entry.buf == buf then
      wins[#wins + 1] = win
    end
  end
  table.sort(wins)
  for _, win in ipairs(wins) do
    M.release(win)
  end
  state.set_attached(buf, false)
end

return M
