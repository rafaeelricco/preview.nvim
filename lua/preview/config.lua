local log = require("preview.log")

local M = {}

---@type preview.Config
M.defaults = {
  default_mode = "markdown",
  keymap = "<leader>tp",
  winbar = { enabled = true },
  view = { gutter = 2, max_width = 0, center = true },
  highlights = {},
  render = {
    heading = {
      icons = { "", "", "", "", "", "" },
      bold = { true, true, true, false, false, false },
    },
    spacing = {
      heading = { above = { 2, 1, 1, 1, 1, 1 }, below = { 1, 1, 1, 1, 1, 1 } },
      paragraph = { above = 1, below = 1 },
      list = { above = 1, below = 1 },
      quote = { above = 1, below = 1 },
      code = { above = 1, below = 1 },
      table = { above = 1, below = 1 },
      rule = { above = 1, below = 1 },
    },
    list = { bullets = { "•", "◦", "▪", "▫" }, gap = 1 },
    checkbox = { checked = "󰄲", unchecked = "󰄱", gap = 1 },
    quote = { bar = "▎" },
    code = { label = false, padding = 2 },
    link = { icon = "", gap = 1 },
    table = { border = true, row_lines = true },
  },
}

--- Options whose default is nil, so `defaults` cannot list them.
---@type table<string, true>
local OPTIONAL = { ["view.wrap"] = true }

--- Whether `value` is a table that vim.tbl_deep_extend would merge into rather
--- than replace: a map, or an empty table. Lists are replaced wholesale.
---@param value any
---@return boolean
local function is_map(value)
  return type(value) == "table" and (vim.tbl_isempty(value) or not vim.islist(value))
end

--- Keys present in `user` but absent from `defaults`, as dotted paths. Pure.
---@param defaults table
---@param user table
---@param prefix string|nil
---@return string[]
function M.unknown_keys(defaults, user, prefix)
  local out = {}
  for key, value in pairs(user) do
    local path = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
    local default = defaults[key]
    if default == nil then
      if not OPTIONAL[path] then out[#out + 1] = path end
    elseif path ~= "highlights" and is_map(default) and is_map(value) then
      vim.list_extend(out, M.unknown_keys(default, value, path))
    end
  end
  table.sort(out)
  return out
end

--- Runs vim.validate (form 1) and returns the failure message instead of throwing.
---@param name string
---@param value any
---@param validator vim.validate.Validator
---@param message string|nil
---@return string|nil
local function check(name, value, validator, message)
  local ok, err = pcall(vim.validate, name, value, validator, false, message)
  if ok then
    return nil
  end
  return tostring(err)
end

--- Validator for a value drawn from a fixed set. Pure.
---@param values any[]
---@return fun(value: any): boolean
local function one_of(values)
  return function(value)
    return vim.list_contains(values, value)
  end
end

---@param value any
---@return boolean
local function is_count(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

--- Validator for a list whose items all satisfy `item_ok`, with `count`
--- entries, or any non-empty length when `count` is nil. Pure.
---@param count integer|nil
---@param item_ok fun(item: any): boolean
---@return fun(value: any): boolean
local function list_of(count, item_ok)
  return function(value)
    if type(value) ~= "table" or not vim.islist(value) then
      return false
    end
    if count and #value ~= count or #value == 0 then
      return false
    end
    for _, item in ipairs(value) do
      if not item_ok(item) then
        return false
      end
    end
    return true
  end
end

---@param count integer|nil
---@return fun(value: any): boolean
local function boolean_list(count)
  return list_of(count, function(item) return type(item) == "boolean" end)
end

---@param count integer|nil
---@return fun(value: any): boolean
local function string_list(count)
  return list_of(count, function(item) return type(item) == "string" end)
end

---@param s preview.SpacingConfig
---@return string|nil
local function validate_spacing(s)
  local err = check("render.spacing.heading", s.heading, "table")
    or check("render.spacing.heading.above", s.heading.above, list_of(6, is_count), "list of exactly 6 integers >= 0")
    or check("render.spacing.heading.below", s.heading.below, list_of(6, is_count), "list of exactly 6 integers >= 0")
  for _, kind in ipairs({ "paragraph", "list", "quote", "code", "table", "rule" }) do
    err = err
      or check("render.spacing." .. kind, s[kind], "table")
      or check("render.spacing." .. kind .. ".above", s[kind].above, is_count, "integer >= 0")
      or check("render.spacing." .. kind .. ".below", s[kind].below, is_count, "integer >= 0")
  end
  return err
end

---@param w preview.WinbarConfig
---@return string|nil
local function validate_winbar(w)
  return check("winbar.enabled", w.enabled, "boolean")
end

---@param value any
---@return boolean
local function is_gutter(value)
  return type(value) == "number" and value >= 0 and value <= 9 and value % 1 == 0
end

---@param value any
---@return boolean
local function is_optional_boolean(value)
  return value == nil or type(value) == "boolean"
end

---@param v preview.ViewConfig
---@return string|nil
local function validate_view(v)
  return check("view.gutter", v.gutter, is_gutter, "integer from 0 to 9")
    or check("view.wrap", v.wrap, is_optional_boolean, "boolean or nil")
    or check("view.max_width", v.max_width, is_count, "integer >= 0")
    or check("view.center", v.center, "boolean")
end

---@param r preview.RenderConfig
---@return string|nil
local function validate_render(r)
  return check("render.heading", r.heading, "table")
    or check("render.heading.icons", r.heading.icons, string_list(6), "list of exactly 6 strings")
    or check("render.heading.bold", r.heading.bold, boolean_list(6), "list of exactly 6 booleans")
    or check("render.spacing", r.spacing, "table")
    or validate_spacing(r.spacing)
    or check("render.list", r.list, "table")
    or check("render.list.bullets", r.list.bullets, string_list(nil), "non-empty list of strings")
    or check("render.list.gap", r.list.gap, is_count, "integer >= 0")
    or check("render.checkbox", r.checkbox, "table")
    or check("render.checkbox.checked", r.checkbox.checked, "string")
    or check("render.checkbox.unchecked", r.checkbox.unchecked, "string")
    or check("render.checkbox.gap", r.checkbox.gap, is_count, "integer >= 0")
    or check("render.quote", r.quote, "table")
    or check("render.quote.bar", r.quote.bar, "string")
    or check("render.code", r.code, "table")
    or check("render.code.label", r.code.label, one_of({ "left", "right", false }), '"left", "right" or false')
    or check("render.code.padding", r.code.padding, is_count, "integer >= 0")
    or check("render.link", r.link, "table")
    or check("render.link.icon", r.link.icon, "string")
    or check("render.link.gap", r.link.gap, is_count, "integer >= 0")
    or check("render.table", r.table, "table")
    or check("render.table.border", r.table.border, "boolean")
    or check("render.table.row_lines", r.table.row_lines, "boolean")
end

--- Validates a fully merged config. Uses vim.validate form 1 per field.
--- Returns nil on success, otherwise the first error message. Pure apart from validate.
--- Every override must be a table keyed by group name. Pure apart from validate.
---@param h table<string, any>
---@return string|nil
local function validate_highlights(h)
  for group, spec in pairs(h) do
    local err = check("highlights." .. tostring(group), spec, "table")
    if err then
      return err
    end
  end
  return nil
end

---@param cfg preview.Config
---@return string|nil
function M.validate(cfg)
  return check("config", cfg, "table")
    or check("default_mode", cfg.default_mode, one_of({ "preview", "markdown" }), '"preview" or "markdown"')
    or check("keymap", cfg.keymap, function(v)
      return type(v) == "string" or v == false
    end, "string or false")
    or check("winbar", cfg.winbar, "table")
    or validate_winbar(cfg.winbar)
    or check("view", cfg.view, "table")
    or validate_view(cfg.view)
    or check("render", cfg.render, "table")
    or validate_render(cfg.render)
    or check("highlights", cfg.highlights, "table")
    or validate_highlights(cfg.highlights)
end

--- Merges user over defaults, warns once per unknown key, validates.
--- Returns the config or nil + error. Never throws.
---@param user table|nil
---@return preview.Config|nil, string|nil
function M.resolve(user)
  local ok, cfg, err = pcall(function()
    if user == nil then
      user = {}
    end
    local type_err = check("config", user, "table")
    if type_err then
      return nil, type_err
    end
    for _, key in ipairs(M.unknown_keys(M.defaults, user)) do
      log.warn_once("config", ("unknown option `%s`"):format(key))
    end
    local merged = vim.deepcopy(vim.tbl_deep_extend("force", M.defaults, user))
    local invalid = M.validate(merged)
    if invalid then
      return nil, invalid
    end
    return merged, nil
  end)
  if not ok then
    return nil, tostring(cfg)
  end
  return cfg, err
end

return M
