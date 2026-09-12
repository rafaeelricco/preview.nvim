local M = {}

---@type string[]
M.SOURCES = { "Normal", "Comment", "CursorLine", "WinSeparator", "DiagnosticInfo" }

---@type table<string, vim.api.keyset.highlight>
local overrides = {}

--- Defaulted, so apply() is safe before setup() has run.
---@type preview.HeadingConfig
local heading_config = require("preview.config").defaults.render.heading

--- Stores user overrides and the heading style. Each override entry is a
--- complete spec that replaces the derived group of the same name on every
--- apply().
---@param specs table<string, vim.api.keyset.highlight>
---@param heading? preview.HeadingConfig  -- omitted leaves the current style
function M.configure(specs, heading)
  overrides = vim.deepcopy(specs)
  if heading then
    heading_config = vim.deepcopy(heading)
  end
end

--- Pure: every Preview* group from the resolved palette groups. Missing colors
--- stay nil so the group inherits, never a literal fallback.
---@param s preview.HighlightSources
---@param heading preview.HeadingConfig
---@return table<string, vim.api.keyset.highlight>
function M.derive(s, heading)
  local fg, bg = s.Normal.fg, s.Normal.bg
  local muted, panel, border, accent = s.Comment.fg, s.CursorLine.bg, s.WinSeparator.fg, s.DiagnosticInfo.fg
  -- Terminals cannot scale text. Weight is the one axis the terminal resolves
  -- to a different font face -- Ghostty draws bold cells with `font-style-bold`
  -- -- so `render.heading.bold` splits the levels and `render.spacing` carries
  -- the rest of the hierarchy.
  local groups = {
    PreviewBold = { fg = fg, bold = true },
    PreviewItalic = { italic = true },
    PreviewCodeBlock = { bg = panel },
    PreviewCodeInline = { fg = fg, bg = panel },
    PreviewCodeLabel = { fg = muted, bg = panel },
    PreviewBullet = { fg = fg },
    PreviewCheckbox = { fg = accent },
    PreviewQuote = { fg = border },
    PreviewLink = { fg = accent, underline = true },
    PreviewTable = { fg = border },
    PreviewTableBody = { fg = fg },
    PreviewTableHeader = { fg = fg, bold = true },
    PreviewRule = { fg = border },
    PreviewWinbar = { fg = muted, bg = bg },
    -- Active button uses the theme's panel surface.
    PreviewButtonActive = { fg = fg, bg = panel, bold = true },
    PreviewButtonInactive = { fg = muted, bg = bg },
  }
  for level = 1, 6 do
    groups["PreviewH" .. level] = { fg = fg, bold = heading.bold[level] }
  end
  return groups
end

--- Resolves the source groups and defines every Preview* group with concrete
--- values, configured overrides replacing derived specs group by group. Not
--- `default`: re-running after a palette change must overwrite.
function M.apply()
  ---@type table<string, vim.api.keyset.get_hl_info>
  local resolved = {}
  for _, name in ipairs(M.SOURCES) do
    resolved[name] = vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  local sources = resolved --[[@as preview.HighlightSources]]
  for group, spec in pairs(vim.tbl_extend("force", M.derive(sources, heading_config), overrides)) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

return M
