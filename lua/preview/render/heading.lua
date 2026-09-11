---@type preview.Element
return {
  name = "heading",
  lang = "markdown",
  query = [[
    (atx_heading
      [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker)
       (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @marker) @root
  ]],
  --- Conceals the marker (plus one trailing space), highlights the source text
  --- by level, prepends the level icon when one is configured and adds the
  --- level's `space_above` virtual blank lines above the heading.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local marker = m.captures.marker[1]
    local level = tonumber(marker:type():match("atx_h(%d)_marker")) or 1
    local row, scol, _, ecol = marker:range()
    local line = ctx.lines(row)
    -- swallow one trailing space; clamp for a bare "#"
    local conceal_end = math.min(ecol + 1, #line)
    local hl = "PreviewH" .. level
    local icon = ctx.config.heading.icons[level] or ""
    ---@type preview.Mark[]
    local marks = {
      { row = row, col = scol, opts = { end_col = conceal_end, conceal = "" } },
      { row = row, col = 0, opts = { end_col = #line, hl_group = hl } },
    }
    if icon ~= "" then
      marks[#marks + 1] = { row = row, col = scol, opts = { virt_text = { { icon .. " ", hl } }, virt_text_pos = "inline" } }
    end
    local space = ctx.config.heading.space_above[level] or 0
    if space > 0 then
      ---@type preview.Chunk[][]
      local blank = {}
      for i = 1, space do
        blank[i] = { { "", hl } }
      end
      marks[#marks + 1] = { row = row, col = 0, opts = { virt_lines = blank, virt_lines_above = true } }
    end
    return marks
  end,
}
