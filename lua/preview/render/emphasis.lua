---@type preview.Element
return {
  name = "emphasis",
  lang = "markdown_inline",
  query = [[ [(emphasis) (strong_emphasis)] @root ]],
  --- Highlights the span and conceals every delimiter child.
  ---@param _ preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(_, m)
    local node = m.root
    local hl = node:type() == "strong_emphasis" and "PreviewBold" or "PreviewItalic"
    local srow, scol, erow, ecol = node:range()
    ---@type preview.Mark[]
    local marks = { { row = srow, col = scol, opts = { end_row = erow, end_col = ecol, hl_group = hl } } }
    for child in node:iter_children() do
      if child:type() == "emphasis_delimiter" then
        local r, c, _, ec = child:range()
        marks[#marks + 1] = { row = r, col = c, opts = { end_col = ec, conceal = "" } }
      end
    end
    return marks
  end,
}
