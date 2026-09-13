---@type preview.Element
return {
  name = "code",
  lang = "markdown",
  query = [[ (fenced_code_block (info_string (language) @lang)?) @root ]],
  --- Source content stays editable; layout supplies bounded panel padding.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[], preview.RowFlow[]
  render = function(ctx, m)
    local srow, scol, erow, ecol = m.root:range()
    if ecol == 0 and erow > srow then erow = erow - 1 end
    ---@type preview.Mark[]
    local marks = {}
    ---@type preview.RowFlow[]
    local flows = {}
    for row = srow, erow do
      local start_col = math.min(scol, #ctx.lines(row))
      marks[#marks + 1] = {
        row = row, col = start_col,
        opts = { end_col = #ctx.lines(row), hl_group = "PreviewCodeBlock" },
      }
      flows[#flows + 1] = {
        row = row, kind = "code", start_col = start_col,
        padding = ctx.config.code.padding, background = "PreviewCodeBlock",
        -- Native wrapping counts these source bytes even once they are
        -- concealed, so layout subtracts them from a fence row's panel fill.
        source_width = vim.fn.strdisplaywidth(ctx.lines(row):sub(start_col + 1)),
      }
    end
    for child in m.root:iter_children() do
      if child:type() == "fenced_code_block_delimiter" then
        local row, col = child:range()
        -- Conceal the delimiter's text only. The row itself stays, and layout
        -- shades it into the panel's padding row: a row removed with
        -- `conceal_lines` next to one carrying `virt_lines` is redrawn
        -- incorrectly while scrolling.
        marks[#marks + 1] = { row = row, col = col, opts = { end_col = #ctx.lines(row), conceal = "" } }
        flows[row - srow + 1].fence = true
      end
    end
    local label = ctx.config.code.label
    local lang = m.captures.lang and m.captures.lang[1]
    if label and lang then
      flows[1].label = vim.treesitter.get_node_text(lang, ctx.buf)
      flows[1].label_position = label
    end
    return marks, flows
  end,
}
