# preview.nvim

Markdown reading view inside the buffer: a winbar with two mode buttons, `Preview` and `Markdown`, plus an in-place renderer built on extmarks and conceal.

## Overview

Each eligible window has a mode. `markdown` shows the raw source; `preview` renders headings, emphasis, lists, checkboxes, block quotes, fenced and inline code, links, pipe tables and horizontal rules in place. Preview remains the same source buffer in the same window: edits go directly to the Markdown while conceal stays active in normal, visual, insert and command-line modes. Named normal buffers are eligible when their filename ends in `.md` or `.markdown`, case-insensitively, regardless of contents or `filetype`; unnamed buffers fall back to `filetype=markdown`. Floating windows, such as LSP hover, are never managed.

```text
click / :Preview / <leader>tp
  -> set_mode(win, mode)          window-local: winbar, preview options (see Preview mode)
  -> state                        win -> mode and managed buffer
  -> render.attach(buf)           first preview window on the buffer
  -> decoration provider          on_start: cache layout and place marks
  -> render.release(win)          window-specific namespace cleanup
  -> render.detach(buf)           last preview window leaves the buffer
```

Mode and persistent rendering are per window; renderer attachment and parsing are shared per buffer. Two windows on the same buffer can be in different modes, and two preview windows do not share extmarks. No external tools; parsing uses the bundled `markdown` and `markdown_inline` Treesitter parsers. Requires Neovim 0.12, including the experimental `nvim__ns_set` API used to scope each persistent namespace to its window.

## Installation

```lua
{
  "rafaeelricco/preview.nvim",
  ft = "markdown",
  event = {
    "BufReadPost *.[mM][dD]",
    "BufNewFile *.[mM][dD]",
    "BufReadPost *.[mM][aA][rR][kK][dD][oO][wW][nN]",
    "BufNewFile *.[mM][aA][rR][kK][dD][oO][wW][nN]",
  },
  opts = {},
}
```

From a local checkout, replace the first line with `dir = "~/Projects/personal/preview.nvim"`.

## Configuration

Defaults:

```lua
require("preview").setup({
  default_mode = "markdown",          -- "markdown" | "preview"
  keymap = "<leader>tp",              -- string | false
  winbar = { enabled = true },
  view = {
    gutter = 2,                       -- minimum left and right margin, 0..9
    wrap = nil,                       -- nil follows the window's 'wrap'; true/false forces it in preview
    max_width = 0,                    -- 0 removes the width cap
    center = true,                    -- false keeps the content at the left gutter
  },
  highlights = {},                    -- full specs that replace derived groups, see Highlights
  render = {
    heading = {
      icons = { "", "", "", "", "", "" },               -- no icons
      bold = { true, true, true, false, false, false },   -- the terminal's bold font face, per level
    },
    spacing = {
      heading = { above = { 3, 2, 2, 1, 1, 1 }, below = { 1, 1, 1, 1, 1, 1 } },
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
    code = { label = false, padding = 2 }, -- label: "left" | "right" | false
    link = { icon = "", gap = 1 },     -- icon: "" for no icon
    table = { border = true, row_lines = true },
  },
})
```

Wrong types fail `setup()` with an error naming the key path. `view.gutter` must be an integer from 0 to 9; `view.wrap`, when set, must be a boolean; `view.max_width` and `render.code.padding` must be nonnegative integers; `render.heading.bold` must be a list of exactly six booleans, one per level; `render.spacing.heading.above` and `render.spacing.heading.below` must each be a list of exactly six nonnegative integers, one per level; every other `render.spacing.*` entry (`paragraph`, `list`, `quote`, `code`, `table` and `rule`, each with `above` and `below`) must be a nonnegative integer; and `render.list.gap`, `render.checkbox.gap` and `render.link.gap` must each be a nonnegative integer. Unknown keys warn once. `setup()` is idempotent.

`render.spacing` is the vertical rhythm preview draws, not the one in the source. The gap shown between two neighbouring blocks is the larger of the previous block's `below` and the next block's `above`, never their sum, so a heading followed by three blank source lines and a paragraph renders with one gap rather than three stacked blank rows. Preview reaches that gap by adjusting the difference: it reuses the source's own blank rows, hides only the surplus, and adds virtual rows only where the source is short. Where the source already matches the rhythm, nothing is drawn or hidden at all.

## Preview mode

Entering `preview` snapshots the window's options and sets `conceallevel=2`, `concealcursor=nvic`, `number=false`, `relativenumber=false`, `signcolumn=no`, `cursorline=false`, `colorcolumn=""`, `foldcolumn=0`, `foldenable=false`, `linebreak=false`, `breakindent=false`, `breakindentopt=""`, `showbreak=""` and `list=false`. Leaving `preview` restores every one of them from the snapshot. `wrap` is left alone unless `view.wrap` is set: unset, preview follows the window's own value from your Neovim setup; `true` or `false` forces it while in preview and restores yours on leaving. A window split from a preview window starts raw with the baseline options, not the inherited preview ones. When a managed window changes buffers, `BufLeave` suspends the outgoing buffer before Neovim switches it and restores that buffer's options; the incoming eligible buffer reinstalls the bar and keymap and reuses the window's selected mode. Preview does not mutate shared buffer options such as `formatlistpat`.

The default layout uses the window width with two cells of padding on each side. Set a positive `max_width` to limit the reading column. Small windows clamp those margins to the available space. `max_width = 0` removes the cap, and `center = false` places the column at the left gutter. Margins and element padding are virtual, so source line breaks and text remain unchanged. With `nowrap`, layout uses only the left gutter: centering is disabled, lines are not force-wrapped, tables stay in grid form instead of becoming stacked fields, and Neovim's native horizontal scrolling remains available; table rules and code panel padding follow the scrolled text. `:set wrap` or `:set nowrap` in a preview window re-lays it out; with `view.wrap` set, preview re-applies its value on the next buffer or window event. `j` and `k` move by source line; use `gj` and `gk` to move by screen line.

Fenced code is shown as a theme-derived rectangular shaded panel. Hidden fence lines contribute virtual blank panel rows so padding remains visible with Neovim’s Markdown highlighting. `render.code.padding` adds bounded virtual padding on each side without changing the code text. With wrapping enabled, a pipe table stays a source-backed grid when its natural width fits the reading column; otherwise it becomes stacked labeled fields. Neither layout copies table body text into virtual lines.

While a window is managed, its window-local `WinBar` and `WinBarNC` highlight mappings point to `Normal`. Cleanup restores only the mappings the plugin owns and preserves unrelated `winhighlight` entries.

## Commands

| Command             | Description                                                |
| ------------------- | ---------------------------------------------------------- |
| `:Preview toggle`   | Switch the current window between `preview` and `markdown` |
| `:Preview preview`  | Render the current window                                  |
| `:Preview markdown` | Show the raw source in the current window                  |

`<leader>tp` (buffer-local, normal mode, `[T]oggle [P]review`) runs `:Preview toggle`. Set `keymap = false` to skip it. Clicking `Preview` or `Markdown` in the winbar does the same.

Lua API: `require("preview").setup(opts)`, `.set_mode(win, mode)`, `.toggle(win?)`, `.mode(win?)`, `.config()`.

## Highlights

Every `Preview*` group is computed from the active palette, not linked to a stock group. `highlights.apply()` resolves `Normal`, `Comment`, `CursorLine`, `WinSeparator` and `DiagnosticInfo` with `nvim_get_hl(0, { name = ..., link = false })` and defines each group with the concrete values below. A color the source group does not define stays unset, so the group inherits it; the plugin never uses a literal color.

| Group                    | Derived from                                |
| ------------------------ | ------------------------------------------- |
| `PreviewH1`..`PreviewH6` | `Normal` fg, bold per `render.heading.bold` |
| `PreviewBold`            | `Normal` fg, bold                           |
| `PreviewItalic`          | italic only                                 |
| `PreviewCodeBlock`       | `CursorLine` bg                             |
| `PreviewCodeInline`      | `Normal` fg, `CursorLine` bg                |
| `PreviewCodeLabel`       | `Comment` fg, `CursorLine` bg               |
| `PreviewBullet`          | `Normal` fg                                 |
| `PreviewCheckbox`        | `DiagnosticInfo` fg                         |
| `PreviewQuote`           | `WinSeparator` fg                           |
| `PreviewLink`            | `DiagnosticInfo` fg, underline              |
| `PreviewTable`           | `WinSeparator` fg                           |
| `PreviewTableHeader`     | `Normal` fg, bold                           |
| `PreviewTableBody`       | `Normal` fg                                 |
| `PreviewRule`            | `WinSeparator` fg                           |
| `PreviewWinbar`          | `Comment` fg, `Normal` bg                   |
| `PreviewButtonActive`    | `Normal` fg, `CursorLine` bg, bold          |
| `PreviewButtonInactive`  | `Comment` fg, `Normal` bg                   |

The groups are re-derived on `ColorScheme` and `OptionSet background` (from a scheduled callback, so a colorscheme that repaints on those events is read after it ran) and are not `default`, so a plain `nvim_set_hl` in your config is overwritten on the next palette change. Override through `setup` instead; each entry is a complete spec that replaces the derived group on every re-derivation:

```lua
require("preview").setup({
  highlights = {
    PreviewLink = { fg = "#8be9fd", underline = true },
  },
})
```

## Validation

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/" -c "qa!"
export VIMRUNTIME="$(nvim --headless -u NONE -i NONE -n -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa!')"
~/.local/share/nvim/mason/bin/lua-language-server --check . --checklevel=Warning
```

The test harness isolates Neovim from your personal configuration and checks composed screen cells as well as renderer output. `VIMRUNTIME` lets LuaLS resolve Neovim's API types.

## Limitations

- Terminals do not provide proportional font sizes or rounded corners, so heading hierarchy comes from weight and `render.spacing`, and code panels are rectangular. A terminal draws bold cells with its own bold font face, so how much heavier the upper levels look is set by your terminal's bold font, not by the plugin: in Ghostty, `font-style-bold` against `font-style`.
- Very long concealed spans can still occupy native wrapped rows, which may appear blank.
- Surplus blank rows between blocks are hidden, not removed, so `j` and `k` still step through them and the cursor can appear to pause on a row you cannot see. Nothing is lost: typing into such a row makes it non-blank and the next redraw shows it again.
- Third-party inline decorations can change display width, so exact alignment with them is not guaranteed.
- Two windows on the same buffer in different modes both work, with rendering scoped to each preview window.
- Not rendered in v1: setext headings, footnotes, HTML blocks, images, multi-line links.
- The last chosen mode is not persisted across sessions.
