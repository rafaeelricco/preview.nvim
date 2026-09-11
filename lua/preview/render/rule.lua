---@type preview.Element
return {
  name = "rule",
  lang = "markdown",
  query = [[ (thematic_break) @root ]],
  --- Hides "---" and draws a line across the text width.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local row = m.root:range()
    return {
      { row = row, col = 0, opts = { end_col = #ctx.lines(row), conceal = "" } },
      { row = row, col = 0, opts = { virt_text = { { ("─"):rep(ctx.width), "PreviewRule" } }, virt_text_pos = "overlay" } },
    }
  end,
}
