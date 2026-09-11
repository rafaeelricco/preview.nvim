---@type preview.Element
return {
  name = "link",
  lang = "markdown_inline",
  query = [[ (inline_link (link_text) @text) @root ]],
  --- Conceals "[" and "](destination)", highlights the text and prepends the
  --- link icon when one is configured. Links spanning more than one line
  --- render raw.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local link, text = m.root, m.captures.text[1]
    local lsr, lsc, ler, lec = link:range()
    local tsr, tsc, ter, tec = text:range()
    if lsr ~= ler then
      return {}
    end
    ---@type preview.Mark[]
    local marks = {
      { row = lsr, col = lsc, opts = { end_col = tsc, conceal = "" } },
      { row = tsr, col = tsc, opts = { end_col = tec, hl_group = "PreviewLink" } },
      { row = ter, col = tec, opts = { end_col = lec, conceal = "" } },
    }
    local icon = ctx.config.link.icon
    if icon ~= "" then
      marks[#marks + 1] = {
        row = tsr,
        col = tsc,
        opts = { virt_text = { { icon .. " ", "PreviewLink" } }, virt_text_pos = "inline" },
      }
    end
    return marks
  end,
}
