# preview.nvim design

Date: 2026-09-10
Status: implemented

## Goal

A Neovim plugin that gives Markdown buffers a bar above the window with two
buttons on the right, `Preview` and `Markdown`.
`Preview` renders the Markdown in place with extmarks and conceal. `Markdown`
shows the raw source. The look follows the Cursor/Obsidian reading-view bar:

```
                                                                                  Preview  [Markdown]
```

## Decisions made during brainstorming

| Decision             | Choice                                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Preview mechanism    | Decorate in place: same buffer, same window, extmarks + conceal                                                     |
| Renderer             | Own implementation, no dependency on render-markdown.nvim                                                           |
| Elements in v1       | Headings, emphasis, lists, checkboxes, block quotes, fenced code, inline code, links, pipe tables, horizontal rules |
| Default mode on open | `markdown` (raw)                                                                                                    |
| Mode scope           | Per window; one persistent, window-scoped namespace per preview window                                              |
| External tools       | None                                                                                                                |
| Minimum Neovim       | 0.12 (experimental `nvim__ns_set`). Author runs 0.12.5                                                              |

## Target environment

Derived from `~/Projects/personal/dotfiles/nvim`:

- Neovim 0.12.5, lazy.nvim, plugin specs under `lua/domains/*.lua`
- Ghostty on macOS, `mouse = "a"`, `wrap = false`, `termguicolors = true`
- `vim.g.have_nerd_font = true`, icons from `DaikyXendo/nvim-material-icon` (exposes the `nvim-web-devicons` module)
- Treesitter `main` branch with `markdown` and `markdown_inline` parsers installed
- Custom colorscheme in `core/profiles.lua` that sets highlight groups directly and switches on `vim.o.background`
- `winbar` is unused by any existing plugin; `mini.statusline` owns the statusline only
- Leader is `<space>`; which-key defines a `[T]oggle` group under `<leader>t`
- Existing plugin conventions from `~/Projects/personal/copy.nvim`: `plugin/<name>.lua` guard, `lua/<name>/`, `tests/minimal_init.lua` with a plenary fallback

## Architecture

Four units with one-way dependencies. Lower units never reference higher ones.

```
plugin/preview.lua               guard, optional auto-setup via vim.g.preview_auto_setup
lua/preview/init.lua             setup(), toggle(), set_mode(win, mode), mode(win)
lua/preview/config.lua           defaults + validation, pure
lua/preview/state.lua            window -> mode, managed buffer and saved window state
lua/preview/ui/winbar.lua        winbar string builder, pure given (mode)
lua/preview/ui/highlights.lua    Preview* highlight groups, derived from the palette (pure derive + apply)
lua/preview/render/init.lua      persistent window-scoped namespaces, provider, full-buffer cache, collect()
lua/preview/render/context.lua   per-redraw snapshot: buffer, window and reading-column layout
lua/preview/render/layout.lua    geometry and RowFlow pipeline for padding, wrapping and stacked fields
lua/preview/render/query.lua     Treesitter queries per element, compiled once
lua/preview/render/heading.lua
lua/preview/render/emphasis.lua
lua/preview/render/list.lua      also handles checkboxes
lua/preview/render/quote.lua
lua/preview/render/code.lua      fenced blocks and inline code spans
lua/preview/render/link.lua
lua/preview/render/table.lua     source-backed grid or stacked labeled fields, chosen by natural width
lua/preview/render/rule.lua      thematic breaks
tests/minimal_init.lua           copied from copy.nvim unchanged
tests/unit/*_spec.lua            one per pure module
tests/integration/toggle_spec.lua
tests/fixtures/*.md
```

### Data flow: click on Preview

1. Winbar click handler calls `set_mode(win, "preview")`.
2. `state` records the mode. If this is the buffer's first preview window, `render.attach(buf)` runs.
3. On the next redraw the provider's single `on_start` pass computes the full-buffer layout before Neovim draws any window and places persistent marks in each preview window's scoped namespace.
4. The winbar expression re-evaluates and swaps the active button highlight.

`Markdown` reverses it. `render.release(win)` clears a window's namespace when
its mode, buffer or lifetime changes. `render.detach(buf)` runs when the last
preview window leaves the buffer.

### Boundaries

- Mode and persistent rendering are per window; attachment and parsing are per buffer. A raw split and a preview split on the same buffer coexist, and separate preview windows use separate scoped namespaces.
- Every element module implements `render(ctx, match, prior_marks?) -> marks, row_flows?`. The optional third argument contains marks already collected by source row; the optional second return describes layout constraints without placing text. Modules never call the Neovim API.
- `render/init.lua` collects element marks and `RowFlow` records, then `render/layout.lua` applies window geometry, virtual padding, hanging indentation, bounded panels and stacked-field breaks before `render/init.lua` places the final specs.

## Renderer

### Mechanism

One decoration provider is registered once. Every preview window owns a persistent namespace configured with experimental `nvim__ns_set` so its extmarks are visible only in that window.

- `on_start`: inspect all active preview windows, build their contexts, collect source marks and `RowFlow` records, run the centralized layout pipeline, and reconcile persistent marks before drawing starts. Full-buffer results are cached by buffer, changed tick, window layout and configuration.

`RowFlow` describes per-source-row behavior for list hanging indentation, code
panel bounds and table field breaks. Elements may return it alongside their
source marks; collection resolves competing flows, then `layout.apply` adds
virtual padding without copying source body text.

No `on_win`, `on_range` or ephemeral placement is used.

The cache covers the full buffer rather than only the viewport. A buffer edit,
width change, configuration change, mode change, buffer change or
window cleanup invalidates the relevant state.

### Parsing

`vim.treesitter.get_parser(buf, "markdown")`, `parser:parse({top, bot})`. Inline
elements live in the injected `markdown_inline` tree; the query runner iterates
`parser:for_each_tree` and runs inline queries against inline trees only.

### Editing and movement

Preview decorates the source buffer in its existing window. `concealcursor=nvic`
keeps the rendered form visible in normal, visual, insert and command-line
modes, including on the cursor line. Edits still change the Markdown source.
Source line breaks are preserved: `j` and `k` move by source line, while `gj`
and `gk` move by screen line.

### Preview window options

Entering preview snapshots the options below on the window and applies the
preview set; leaving restores the snapshot.

| Option           | Preview value |
| ---------------- | ------------- |
| `conceallevel`   | `2`           |
| `concealcursor`  | `"nvic"`      |
| `number`         | `false`       |
| `relativenumber` | `false`       |
| `signcolumn`     | `"no"`        |
| `cursorline`     | `false`       |
| `colorcolumn`    | `""`          |
| `foldcolumn`     | `"0"`         |
| `foldenable`     | `false`       |
| `wrap`           | `view.wrap`   |
| `linebreak`      | `false`       |
| `breakindent`    | `false`       |
| `breakindentopt` | `""`          |
| `showbreak`      | `""`          |
| `list`           | `false`       |

The renderer creates the gutter and reading-column layout with virtual
padding. It does not use `foldcolumn` for layout or mutate shared buffer
options such as `formatlistpat`.

By default, the reading column is at most 100 cells wide and centered with a
minimum four-cell margin on both sides. Tiny windows clamp the margins to the
space available. `view.max_width = 0` removes the width cap;
`view.center = false` keeps the content at the left gutter. When
`view.wrap = false`, layout uses only the left gutter: it disables centering,
does not force screen wrapping, keeps tables as grids instead of stacking
their fields, and leaves native horizontal scrolling available; table rules and code panel padding follow the scrolled text.

A window split from a preview window inherits the preview values; when the
plugin manages it, the saved table of a managed sibling on the same buffer is
the pre-plugin baseline and is applied so the split starts raw. `BufLeave`
suspends the outgoing buffer before the switch and restores its owned options.
The next eligible buffer reconciles the bar, keymap and options while preserving
the mode selected in that window. Cleanup on mode, buffer or window changes
restores the state owned by the plugin.

### Element modules

| Module          | Nodes                                                                                                                                        | Rendering                                                                                                                                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| heading         | `atx_heading`, `atx_h1_marker`..`atx_h6_marker`                                                                                              | Conceal the marker, apply the level's `hl_group` to the source range, and add the configured icon and spacing.                                                                                             |
| emphasis        | `emphasis`, `strong_emphasis`, `emphasis_delimiter`                                                                                          | Conceal delimiters and highlight the source text.                                                                                                                                                          |
| list            | `list_marker_minus`, `list_marker_star`, `list_marker_plus`, `list_marker_dot`, `list_marker_parenthesis`; depth = count of `list` ancestors | Overlay unordered markers with the bullet selected by depth; keep and highlight native ordered numbers; return hanging-indent `RowFlow` records.                                                           |
| list (checkbox) | `task_list_marker_checked`, `task_list_marker_unchecked`                                                                                     | Overlay the source marker with the configured icon.                                                                                                                                                        |
| quote           | `block_quote_marker`                                                                                                                         | Overlay `>` with a vertical bar.                                                                                                                                                                           |
| code            | `fenced_code_block`, `fenced_code_block_delimiter`, `info_string`                                                                            | Highlight each source span and return `RowFlow` records that build a theme-derived rectangular panel bounded to the reading column, with `code.padding` virtual cells and an optional language label.      |
| code (inline)   | `code_span`, `code_span_delimiter`                                                                                                           | Highlight the span and conceal each backtick to one shaded padding cell.                                                                                                                                   |
| link            | `inline_link`, `link_text`, `link_destination`                                                                                               | Conceal punctuation and destination, highlight the source label and optionally prefix the configured icon.                                                                                                 |
| table           | `pipe_table`, `pipe_table_header`, `pipe_table_delimiter_row`, `pipe_table_row`, `pipe_table_cell`                                           | Keep source text as the body: with wrapping enabled, use a grid when its natural width fits and otherwise return `RowFlow` field breaks for stacked labeled fields; with wrapping disabled, keep the grid. |
| rule            | `thematic_break`                                                                                                                             | Conceal the source and overlay a rule across the reading column.                                                                                                                                           |

Table layout measures the natural display width of the source-backed cells.
When the grid fits, virtual padding and borders align its columns. With
wrapping enabled, an over-wide grid becomes stacked labeled fields; with
wrapping disabled, it remains a grid for native horizontal scrolling. Both
forms decorate the source text directly; they do not conceal whole rows or
copy body text into virtual lines. Horizontal rules span the reading column.

### Error handling

Each element call is wrapped in `pcall`. A failure logs once per module per
session at `WARN` and the element is skipped for that line. The winbar and mode
toggle never depend on the renderer succeeding.

## Winbar

### Contents

`%=` then two segments, `Preview` and `Markdown`. The active one uses
`PreviewButtonActive`, the other `PreviewButtonInactive`. Each is wrapped in a
click handler that calls `set_mode` for the clicked window.

### Placement

Set with `vim.wo[win].winbar`, never the global option. The value is
`%{%v:lua.require'preview.ui.winbar'.render()%}` (evaluated in the owning window, so the builder reads `nvim_get_current_win()`) so it is
rebuilt on each redraw.

While the bar is managed, the window-local `WinBar` and `WinBarNC` entries in
`winhighlight` map to `Normal`. Cleanup restores the mappings the plugin owns
and leaves unrelated entries unchanged.

## State and events

- `state.windows[win]` is a `WindowState` entry containing the managed buffer, mode, suspension flag and saved window state; a new entry's mode comes from `config.default_mode` unless that window already selected one.
- `state.attached[buf] = true` while at least one preview window uses the buffer.

Named buffers must be normal and use an `.md` or `.markdown` suffix,
case-insensitively, independent of contents and `filetype`. Unnamed buffers use
`filetype=markdown` as a fallback, including scratch `nofile` buffers.

The `BufReadPost` and `BufNewFile` patterns in the lazy.nvim examples only
load the plugin for matching filenames. Once loaded, the plugin registers the
following handlers:

Temporary autocmd windows used by buffer APIs are excluded from managed state.

| Event                                                     | Action                                                                                  |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `FileType`, `BufEnter`, `BufWinEnter`, `BufFilePost`      | reconcile every window showing the affected buffer against current eligibility          |
| `BufLeave`                                                | suspend the outgoing buffer and restore its options before the switch                   |
| `WinNew`                                                  | initialise a new split from the managed sibling's baseline                              |
| `WinClosed`                                               | drop the window entry; detach the renderer if it was the buffer's last preview window   |
| `BufWipeout`                                              | detach unconditionally and drop entries                                                 |
| `BufWinEnter` on an ineligible buffer in a managed window | clear owned UI/render state and restore saved window options                            |
| `ColorScheme`                                             | `vim.schedule(highlights.apply)`: re-derive every `Preview*` group from the new palette |
| `OptionSet` on `background`                               | same as `ColorScheme`                                                                   |

## Commands and keys

- `:Preview toggle`, `:Preview preview`, `:Preview markdown` (one command with completion for the three subcommands)
- Keymap from config, default `<leader>tp`, description `[T]oggle [P]review`, set with `buffer = true` for eligible buffers only. `false` disables.

## Configuration

```lua
require("preview").setup({
  default_mode = "markdown",          -- "markdown" | "preview"
  keymap = "<leader>tp",              -- string | false
  winbar = { enabled = true },
  view = {
    gutter = 4,
    wrap = true,
    max_width = 100,                  -- 0 removes the width cap
    center = true,
  },
  highlights = {},                    -- full specs that replace derived groups
  render = {
    heading = { icons = { "", "", "", "", "", "" }, space_above = { 2, 1, 0, 0, 0, 0 } }, -- no icons; virtual blank lines above each level
    list = { bullets = { "•", "◦", "▪", "▫" } },
    checkbox = { checked = "󰄲", unchecked = "󰄱" },
    quote = { bar = "▎" },
    code = { label = false, padding = 2 }, -- label: "left" | "right" | false
    link = { icon = "" },             -- "" for no icon
    table = { border = true, row_lines = true },
  },
})
```

Validation lives in `config.lua`: wrong types error with the key path; unknown
keys warn once. `view.gutter` must be an integer from 0 to 9.
`view.max_width` and `render.code.padding` must be nonnegative integers; `render.heading.space_above` must be a list of exactly six nonnegative integers, one per level. `view.center` and `view.wrap` are booleans. `setup()`
is idempotent.

## Theming

Every `Preview*` group is computed, not linked. `highlights.apply()` resolves
the source groups `Normal`, `Comment`, `CursorLine`, `WinSeparator` and
`DiagnosticInfo` with `nvim_get_hl(0, { name = ..., link = false })`, hands
them to the pure `derive(sources)` and defines each group with the result
through `nvim_set_hl`. A color a source group does not define stays `nil`, so
the group inherits it; the plugin never uses a literal color.

| Group                    | Derived from                       |
| ------------------------ | ---------------------------------- |
| `PreviewH1`..`PreviewH6` | `Normal` fg, bold                  |
| `PreviewBold`            | `Normal` fg, bold                  |
| `PreviewItalic`          | italic only                        |
| `PreviewCodeBlock`       | `CursorLine` bg                    |
| `PreviewCodeInline`      | `Normal` fg, `CursorLine` bg       |
| `PreviewCodeLabel`       | `Comment` fg, `CursorLine` bg      |
| `PreviewBullet`          | `Normal` fg                        |
| `PreviewCheckbox`        | `DiagnosticInfo` fg                |
| `PreviewQuote`           | `WinSeparator` fg                  |
| `PreviewLink`            | `DiagnosticInfo` fg, underline     |
| `PreviewTable`           | `WinSeparator` fg                  |
| `PreviewTableHeader`     | `Normal` fg, bold                  |
| `PreviewTableBody`       | `Normal` fg                        |
| `PreviewRule`            | `WinSeparator` fg                  |
| `PreviewWinbar`          | `Comment` fg, `Normal` bg          |
| `PreviewButtonActive`    | `Normal` fg, `CursorLine` bg, bold |
| `PreviewButtonInactive`  | `Comment` fg, `Normal` bg          |

`PreviewButtonActive` combines `Normal` foreground with `CursorLine`
background and bold text, without a literal color.

The groups are not `default`: `apply` runs from a scheduled callback on
`ColorScheme` and `OptionSet background` (after `core/profiles.lua` has
repainted on the same events) and overwrites any earlier definition. User
overrides go through `setup({ highlights = { Group = spec } })`: each entry
is a complete spec that replaces the derived group of that name on every
apply, so it survives palette changes. A plain `nvim_set_hl` in a config
file is lost on the next palette change.

## Testing

`render/init.lua` exposes collection helpers for focused unit coverage. The
integration suite also attaches a synthetic embedded UI and asserts the
composed screen, exercising conceal, virtual lines and window-scoped marks.

- `tests/unit/config_spec.lua`: defaults, validation errors, unknown-key warning, idempotent setup
- `tests/unit/winbar_spec.lua`: string contains `%=`, both click handlers, correct active group
- `tests/unit/render/<element>_spec.lua`: scratch buffer with fixture text, real Treesitter parse, assert specs
- `tests/integration/toggle_spec.lua`: open fixture, toggle, assert `conceallevel`, winbar set, state entries, cleanup on `WinClosed`
- `tests/integration/screen_spec.lua`: synthetic embedded UI composed-screen assertions

Runner:

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"
```

## Dotfiles integration

Add to `lua/domains/editor.lua`:

```lua
{
  dir = "~/Projects/personal/preview.nvim",
  ft = "markdown",
  event = {
    "BufReadPost *.[mM][dD]",
    "BufNewFile *.[mM][dD]",
    "BufReadPost *.[mM][aA][rR][kK][dD][oO][wW][nN]",
    "BufNewFile *.[mM][aA][rR][kK][dD][oO][wW][nN]",
  },
  opts = {},
},
```

Nothing else changes: parsers, Nerd Font, mouse support and the `[T]oggle`
which-key group already exist.

## Out of scope for v1

- Setext headings, footnotes, HTML blocks, images
- Persisting the last chosen mode across sessions
- Terminal graphics (Ghostty supports the Kitty protocol; can be added later)

## Known limitations

- Terminals do not provide proportional font sizes or rounded corners; headings use emphasis and code panels are rectangular.
- Very long concealed spans may occupy native wrapped rows that appear blank.
- Exact alignment with third-party inline decorations is not guaranteed because they can change display width.
- Two windows on the same buffer in different modes both work, with rendering scoped to each preview window.
- The name `preview.nvim` collides with an existing plugin on GitLab (`itaranto/preview.nvim`). Decide before publishing.
