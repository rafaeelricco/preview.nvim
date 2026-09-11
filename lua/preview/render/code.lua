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
      }
    end
    for child in m.root:iter_children() do
      if child:type() == "fenced_code_block_delimiter" then
        local row, col = child:range()
        marks[#marks + 1] = { row = row, col = col, opts = { end_col = #ctx.lines(row), conceal = "", conceal_lines = "" } }
        flows[row - srow + 1].fence = true
        local anchor = row == srow and math.min(row + 1, erow) or math.max(row - 1, srow)
        marks[#marks + 1] = {
          row = anchor, col = 0,
          opts = { virt_lines = { { { string.rep(" ", ctx.width), "PreviewCodeBlock" } } },
            virt_lines_above = row == srow },
        }
      end
    end
    local label = ctx.config.code.label
    local lang = m.captures.lang and m.captures.lang[1]
    if label and lang then
      flows[1].label = vim.treesitter.get_node_text(lang, ctx.buf)
      flows[1].label_position = label
      local text = " " .. flows[1].label .. " "
      while vim.fn.strdisplaywidth(text) > ctx.width do
        text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text, true) - 1, true)
      end
      local remaining = math.max(ctx.width - vim.fn.strdisplaywidth(text), 0)
      for _, mark in ipairs(marks) do
        if mark.opts.virt_lines_above then
          local space = { string.rep(" ", remaining), "PreviewCodeBlock" }
          local caption = { text, "PreviewCodeLabel" }
          mark.opts.virt_lines = { label == "left" and { caption, space } or { space, caption } }
        end
      end
    end
    return marks, flows
  end,
}
