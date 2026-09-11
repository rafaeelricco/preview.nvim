local M = {}

---@type string[]
M.SOURCES = { "Normal", "Comment", "CursorLine", "WinSeparator", "DiagnosticInfo" }

---@type table<string, vim.api.keyset.highlight>
local overrides = {}

--- Stores user overrides. Each entry is a complete spec that replaces the
--- derived group of the same name on every apply().
---@param specs table<string, vim.api.keyset.highlight>
function M.configure(specs)
  overrides = vim.deepcopy(specs)
end

--- Pure: every Preview* group from the resolved palette groups. Missing colors
--- stay nil so the group inherits, never a literal fallback.
---@param s preview.HighlightSources
---@return table<string, vim.api.keyset.highlight>
function M.derive(s)
  local fg, bg = s.Normal.fg, s.Normal.bg
  local muted, panel, border, accent = s.Comment.fg, s.CursorLine.bg, s.WinSeparator.fg, s.DiagnosticInfo.fg
  --- Terminals cannot scale text; every level is the text color, bold, and
  --- the hierarchy comes from `render.heading.space_above`.
  ---@return vim.api.keyset.highlight
  local function heading()
    return { fg = fg, bold = true }
  end
  return {
    PreviewH1 = heading(),
    PreviewH2 = heading(),
    PreviewH3 = heading(),
    PreviewH4 = heading(),
    PreviewH5 = heading(),
    PreviewH6 = heading(),
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
  for group, spec in pairs(vim.tbl_extend("force", M.derive(sources), overrides)) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

return M
