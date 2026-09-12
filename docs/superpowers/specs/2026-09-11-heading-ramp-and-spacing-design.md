# Heading ramp and vertical rhythm design

Date: 2026-09-11
Status: implemented

## Goal

Two changes to preview mode, both visible in `tests/fixtures/elements.md`:

1. Headings render with a real per-level ramp. Today `PreviewH1`..`PreviewH6`
   are one helper returning `{ fg = Normal.fg, bold = true }`, so the only
   difference between an H1 and an H6 is how many blank lines sit above it.
2. Preview owns its vertical rhythm. Today `render.heading.space_above` is the
   only spacing control in the renderer, and source blank lines pass through
   1:1, so preview inherits the raw file's rhythm and stacks gaps on top of it.

Tables are out of scope; their width problem is already resolved.

## What a terminal cannot do

The target screenshot is a mockup with proportional font scaling and rounded
code-panel corners. Neither is reachable, and this was verified rather than
assumed:

- **Kitty text sizing protocol (OSC 66).** Ghostty 1.3.1 ships a
  `kitty_text_sizing` parser only. [ghostty#10333][g] is open: cell association
  and renderer work remain, and the maintainers intend to support the `width`
  key first, like foot, not scaling. Neovim is the harder blocker regardless:
  0.12.5 runtime docs mention neither text sizing nor OSC 66,
  [neovim#32539][n] is open and unassigned with a `needs-owner` milestone, no
  extmark field emits OSC 66, and raw escapes written by a plugin are overdrawn
  on the next redraw and desync Neovim's width accounting.
- **Kitty graphics.** Ghostty implements it fully, including virtual
  placements. Rejected anyway: rasterizing heading text needs an external tool,
  the image does not participate in extmark layout, wrapping or conceal, and
  text covered by a picture of itself is not editable.
- **Multi-cell half-block glyphs.** Pure Lua and terminal-agnostic, but a
  three-row glyph means concealing the heading's real line and redrawing its
  text into `virt_lines`. That is copying source text into virtual lines and it
  ends in-place editing for that row. Rejected on the project's own constraint.

None of render-markdown.nvim, markview.nvim or headlines.nvim changes font
size either. They ramp color, weight, width, padding, icons, and — in
render-markdown and headlines — draw `▄`/`▀` half-block rows to fake a taller
band. That is the available design space, and this spec stays inside it.

[g]: https://github.com/ghostty-org/ghostty/issues/10333
[n]: https://github.com/neovim/neovim/issues/32539

## Decisions

| Decision                     | Choice                                                                                    |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| Heading mechanism            | Terminal-native only: per-level foreground, weight, optional band, optional border, icons |
| Size emulation               | None. Hierarchy comes from the foreground ramp and the vertical rhythm                    |
| Band and border defaults     | Off at every level; the screenshot shows neither. Retained as knobs for a stronger H1     |
| Spacing model                | CSS-style margin collapsing, `max(below[prev], above[next])`, never a sum                 |
| Surplus source blanks        | Concealed with `conceal_lines`, so preview owns the gap                                   |
| `render.heading.space_above` | Retired into `render.spacing.heading.above`; its semantics change, so it cannot survive   |
| Rhythm placement             | Its own element module, not spacing threaded through each existing element                |

## Measured starting point

`elements.md` rendered at 80 columns today: the H1→H2 gap is two rows (one
source blank plus `space_above`), every H3..H6 gap is one row, the three source
blanks after "Heading six" pass straight through, and two adjacent code blocks
produce panel-pad, blank, blank, panel-pad.

Two probes shaped the design:

- `conceal_lines` hides a blank row and **stays hidden under the cursor** —
  `concealcursor` does not reveal it. Typing into a collapsed row makes it
  non-blank, so the next render restores it. The mechanism is self-correcting.
- `virt_lines_above` on row 0 does not display, so a leading margin at the top
  of a document is inherently a no-op. No special case is needed for it.
- The markdown grammar nests a `section` per heading level, so top-level blocks
  are **not** flat children of `document`. A walker must descend through
  `section` nodes to recover document order.

## Config surface

```lua
render = {
  heading = {
    icons  = { "", "", "", "", "", "" },
    bold   = { true, true, true, false, false, false },
    fade   = { 0, 0.1, 0.35, 0.6, 0.8, 1 },        -- blend Normal fg toward Comment fg
    band   = { false, false, false, false, false, false },
    border = { false, false, false, false, false, false },
  },
  spacing = {
    heading   = { above = { 3, 2, 2, 1, 1, 1 }, below = { 1, 1, 1, 1, 1, 1 } },
    paragraph = { above = 1, below = 1 },
    list      = { above = 1, below = 1 },
    quote     = { above = 1, below = 1 },
    code      = { above = 1, below = 1 },
    table     = { above = 1, below = 1 },
    rule      = { above = 1, below = 1 },
  },
  list     = { bullets = { "•", "◦", "▪", "▫" }, gap = 1 },
  checkbox = { checked = "󰄲", unchecked = "󰄱", gap = 1 },
  link     = { icon = "", gap = 1 },
  code     = { label = false, padding = 2 },
}
```

`render.heading.space_above` is removed. Parallel six-element lists match the
existing `icons` shape and reuse the `list_of(6, …)` validator.

`code.above` and `code.below` are 1. A panel's own padding rows are not enough
to separate two adjacent blocks: they carry the same background, so touching
panels merge into a single slab. One plain row between them keeps each block
legible as its own panel.

## Heading ramp

`highlights.derive(sources)` gains the heading style as a second argument and
stays pure; `apply()` passes what `configure()` stored, exactly as it already
does for overrides. `configure()` takes the heading style alongside the
override specs.

A pure `blend(from, to, alpha) -> integer` helper mixes two resolved colors per
channel. `PreviewH<n>` becomes `{ fg = blend(Normal.fg, Comment.fg, fade[n]),
bold = bold[n] }`, plus `bg` when `band[n]`. The band background is
`blend(Normal.bg, Normal.fg, 0.06)` so it derives from the palette; the plugin
still never uses a literal color, and a source group that does not define a
color still leaves the derived field nil so the group inherits.

Six new `PreviewH<n>Border` groups carry `{ fg = band bg, bg = Normal.bg }` for
the `▄`/`▀` rows. They are defined unconditionally and used only where
`border[n]` is set, keeping derivation independent of which levels are on.

The heading element gains, per level: the band drawn across the reading column
(`ctx.left` .. `ctx.left + ctx.width`) through layout padding rather than
`hl_eol`, so centering is respected; and the border rows as `virt_lines` above
and below, which add no source text to virtual lines.

## Vertical rhythm

New element `lua/preview/render/rhythm.lua`, registered **first** in
`elements.lua`. Marks are created in registry order and two `virt_lines_above`
marks on one row render in that order, so rhythm's gap sits above a code
panel's top row without needing `prior_marks` at all.

Query: `(document) @root`, one match per buffer.

```
blocks(document)
  for each named child in order
    section      -> recurse
    anything else -> emit { kind, level?, srow, erow, anchor }
```

`erow` uses the same end-column adjustment `code.lua` already applies
(`ecol == 0 and erow > srow` → `erow - 1`). Node type maps to spacing key:
`atx_heading` → `heading` with the level read from its marker child;
`paragraph` → `paragraph`; `list` → `list`; `block_quote` → `quote`;
`fenced_code_block` and `indented_code_block` → `code`; `pipe_table` → `table`;
`thematic_break` → `rule`. Any other type falls back to `paragraph`.

`anchor` is the block's first **visible** row, found by scanning `srow`..`erow`
for the first row that is not one of the block's own
`fenced_code_block_delimiter` children. A block whose every row is a fence — an
unclosed one-line fence — has no visible row and yields `nil`, and then no gap
is emitted at all: a `virt_lines` mark on a `conceal_lines` row renders nothing.

`erow` also drops trailing blank rows. The grammar lets a list's range run past
its last item and even into the next block's first row, so without the trim
those blanks count as _inside_ the list, survive, and the gap stacks on top of
them — the very defect this element exists to remove.

For each consecutive pair `(a, b)`:

1. `want = max(below(a), above(b))`, reading the per-level list for headings.
2. Count the blank source rows strictly between `a.erow` and `b.srow`.
3. Adjust the difference: hide the surplus with `{ conceal_lines = "" }` when
   there are more than `want`, or add the shortfall as empty `virt_lines`
   above `b.anchor` when there are fewer. Equal, and nothing is emitted.

Adjusting the difference rather than replacing the gap wholesale is load-bearing,
not an optimisation. A row hidden with `conceal_lines` sitting next to a row
carrying `virt_lines_above` makes Neovim redraw a wrapped row twice while
scrolling incrementally, which shows up as flicker and repeated paragraphs. The
two mark kinds can never co-occur in one gap under this rule.

Step 3 has one wrinkle. When `b.anchor` already carries a `virt_lines_above`
mark — the code panel's top row — the two must render in the right order. Marks
are created in element-registry order and render in that order, so registering
rhythm **first** puts its gap above the panel. No `prior_marks` needed.

Rows inside a block are never touched, so blank lines inside fenced code and
between loose list items survive untouched. Per-item list spacing is out of
scope. Trailing blank rows at end of file are left alone. A gap before the
first block is emitted but does not display, per the probe above.

## Inline spacing

Three hardcoded single spaces become configured gaps: the list bullet, the
checkbox icon and the link icon. Each renders as `icon .. (" "):rep(gap)`, with
the marker's trailing source space folded into the concealed range so the gap
is exactly `gap` cells regardless of source.

`list.gap` has a consequence worth stating: `list.lua` currently derives the
hanging `indent` from source columns. With a configurable gap it must derive
from the rendered prefix width instead, which `layout_spec` and `list_spec`
already constrain.

`render.code.padding` is unchanged. Inline code chip padding stays at one cell
per backtick — the screenshot matches the current behavior, so it gains no key.

## Testing

- `tests/unit/render/rhythm_spec.lua` — new. Block flattening through nested
  `section` nodes; collapsing takes the max, not the sum; blanks inside fenced
  code untouched; anchor lands past a concealed fence; gap prepends into an
  existing `virt_lines_above` mark rather than adding a second one.
- `tests/unit/render/heading_spec.lua` — per-level weight, fade, band and
  border marks; `space_above` assertions removed.
- `tests/unit/highlights_spec.lua` — the blend ramp, band backgrounds and the
  six Border groups.
- `tests/unit/config_spec.lua` — new keys validate and reject wrong shapes;
  `render.heading.space_above` is reported as unknown.
- `tests/unit/render/list_spec.lua`, `layout_spec.lua` — gap-driven indent.
- `tests/integration/screen_spec.lua` — composed screen for a six-level heading
  ladder and for the `elements.md` rhythm, including two adjacent code panels.
  This is the case that actually proves the result.

## README

The defaults block gains `spacing`, the heading style lists and the three gap
keys; `space_above` leaves it. The highlights table gains
`PreviewH1Border`..`PreviewH6Border` and restates `PreviewH1`..`PreviewH6` as a
derived ramp. The validation paragraph covers the new shapes. Limitations gains
one honest line: terminals provide no proportional font sizes and no rounded
corners, so the heading ramp emulates hierarchy through color, weight and
rhythm rather than reproducing a scaled-type design.

## Out of scope

Setext headings (still unrendered in v1), per-list-item spacing, trailing
end-of-file blanks, table width, and any inline chip padding key.
