---@type preview.Element
return {
  name = "link",
  lang = "markdown_inline",
  query = [[ (inline_link (link_text) @text (link_destination)? @dest) @root ]],
  --- Conceals "[" and "](destination)", highlights the text and prepends the
  --- link icon when one is configured. Links spanning more than one line
  --- render raw. The destination rides on the text's highlight mark as `url`,
  --- which drives `gx` and the terminal's OSC 8 hyperlink without depending on
  --- the bundled markdown_inline query. The capture is optional because a
  --- required one would make the pattern conjunctive, so `[text]()` would stop
  --- matching and render raw.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local link, text = m.root, m.captures.text[1]
    local dest = m.captures.dest and m.captures.dest[1]
    local lsr, lsc, ler, lec = link:range()
    local tsr, tsc, ter, tec = text:range()
    if lsr ~= ler then
      return {}
    end
    ---@type preview.Mark[]
    local marks = {
      { row = lsr, col = lsc, opts = { end_col = tsc, conceal = "" } },
      { row = tsr, col = tsc, opts = {
        end_col = tec,
        hl_group = "PreviewLink",
        url = dest and vim.treesitter.get_node_text(dest, ctx.buf) or nil,
      } },
      { row = ter, col = tec, opts = { end_col = lec, conceal = "" } },
    }
    local icon = ctx.config.link.icon
    if icon ~= "" then
      marks[#marks + 1] = {
        row = tsr,
        col = tsc,
        opts = { virt_text = { { icon .. (" "):rep(ctx.config.link.gap), "PreviewLink" } }, virt_text_pos = "inline" },
      }
    end
    return marks
  end,
}
