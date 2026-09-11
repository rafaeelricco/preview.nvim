---@type preview.Element
return {
  name = "quote",
  lang = "markdown",
  -- The first ">" of a line is a block_quote_marker; on continuation lines of a
  -- nested quote the outer ">" is part of a block_continuation, so both match.
  query = [[ [(block_quote_marker) (block_continuation)] @root ]],
  --- Inserts the configured bar on every ">" inside the node.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local row, col = m.root:range()
    local text = vim.treesitter.get_node_text(m.root, ctx.buf)
    ---@type preview.Mark[]
    local marks = {}
    for offset = 1, #text do
      if text:sub(offset, offset) == ">" then
        marks[#marks + 1] = {
          row = row,
          col = col + offset - 1,
          opts = { end_col = col + offset, conceal = "", virt_text = { { ctx.config.quote.bar, "PreviewQuote" } }, virt_text_pos = "inline" },
        }
      end
    end
    return marks
  end,
}
