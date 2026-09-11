---@type preview.Element
return {
  name = "code_span",
  lang = "markdown_inline",
  query = [[ (code_span) @root ]],
  --- Highlights the span; each backtick becomes one space in the chip color,
  --- which is the chip's padding.
  ---@param _ preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(_, m)
    local node = m.root
    local srow, scol, erow, ecol = node:range()
    ---@type preview.Mark[]
    local marks = {
      { row = srow, col = scol, opts = { end_row = erow, end_col = ecol, hl_group = "PreviewCodeInline" } },
    }
    for child in node:iter_children() do
      if child:type() == "code_span_delimiter" then
        local r, c, _, ec = child:range()
        marks[#marks + 1] = { row = r, col = c, opts = { end_col = ec, conceal = " ", hl_group = "PreviewCodeInline" } }
      end
    end
    return marks
  end,
}
