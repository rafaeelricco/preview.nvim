---@alias preview.Mode "preview"|"markdown"
---@alias preview.Lang "markdown"|"markdown_inline"

---@class preview.WinbarConfig
---@field enabled boolean

---@class preview.RenderConfig
---@field heading preview.HeadingConfig
---@field spacing preview.SpacingConfig
---@field list { bullets: string[], gap: integer }
---@field checkbox { checked: string, unchecked: string, gap: integer }
---@field quote { bar: string }
---@field code { label: "left"|"right"|false, padding: integer }
---@field link { icon: string, gap: integer }
---@field table { border: boolean, row_lines: boolean }

---@class preview.HeadingConfig  -- one entry per level, H1..H6
---@field icons string[]
---@field bold boolean[]  -- the terminal draws bold cells with its bold font face

---@alias preview.Margin { above: integer, below: integer }

---@class preview.SpacingConfig  -- blank rows between blocks; neighbours collapse to the larger
---@field heading { above: integer[], below: integer[] }
---@field paragraph preview.Margin
---@field list preview.Margin
---@field quote preview.Margin
---@field code preview.Margin
---@field table preview.Margin
---@field rule preview.Margin

---@class preview.ViewConfig  -- reading-column layout
---@field gutter integer      -- 0..9 minimum margin cells
---@field wrap? boolean       -- nil follows the window's 'wrap'; set, preview forces it
---@field max_width integer   -- 0 removes the cap
---@field center boolean

---@class preview.View : preview.ViewConfig  -- the config plus the window's own 'wrap'
---@field wrap boolean

---@class preview.Config
---@field default_mode preview.Mode
---@field keymap string|false
---@field winbar preview.WinbarConfig
---@field view preview.ViewConfig
---@field render preview.RenderConfig
---@field highlights table<string, vim.api.keyset.highlight>  -- full specs that replace derived groups

---@class preview.Context  -- frozen per redraw, per window
---@field buf integer
---@field win integer
---@field width integer      -- reading column width
---@field window_width integer
---@field left integer
---@field leftcol integer     -- cells the window is scrolled right; 0 when wrapping
---@field view preview.View
---@field tabstop integer
---@field vartabstop string
---@field display_signature string
---@field top integer        -- 0-based inclusive
---@field bot integer        -- 0-based inclusive
---@field tick integer       -- b:changedtick at snapshot
---@field lines fun(row: integer): string  -- memoised line getter, "" when out of range
---@field config preview.RenderConfig

---@class preview.Mark
---@field row integer
---@field col integer
---@field opts vim.api.keyset.set_extmark  -- stored decorations, never ephemeral

---@alias preview.Chunk { [1]: string, [2]: string }

---@class preview.Field
---@field start_col integer
---@field end_col integer
---@field label? string

---@class preview.RowFlow
---@field row integer
---@field kind "list"|"code"|"table"
---@field indent? integer -- displayed hanging indentation
---@field start_col? integer -- source content starts after a container prefix
---@field padding? integer
---@field background? string
---@field fence? boolean
---@field label? string
---@field label_position? "left"|"right"
---@field fields? preview.Field[] -- force a screen break before each field


---@class preview.Element
---@field name string
---@field lang preview.Lang
---@field query string  -- Treesitter query source; every pattern must capture @root
---@field render fun(ctx: preview.Context, match: preview.Match, prior_marks?: table<integer, preview.Mark[]>): preview.Mark[], preview.RowFlow[]?

---@class preview.Match
---@field root TSNode
---@field captures table<string, TSNode[]>  -- capture name -> nodes, "root" always present

---@class preview.WindowState
---@field buf integer
---@field suspended? boolean
---@field bar_managed boolean
---@field saved_bar_mappings table<string, string>
---@field mode preview.Mode
---@field saved_options table<string, any>  -- window options as they were before preview mode
---@field saved_winbar string
---@field view? vim.fn.winsaveview.ret  -- the scroll position BufLeave suspended it with

---@class preview.HighlightSources  -- resolved palette groups highlights derive from
---@field Normal vim.api.keyset.get_hl_info
---@field Comment vim.api.keyset.get_hl_info
---@field CursorLine vim.api.keyset.get_hl_info
---@field WinSeparator vim.api.keyset.get_hl_info
---@field DiagnosticInfo vim.api.keyset.get_hl_info

return {}
