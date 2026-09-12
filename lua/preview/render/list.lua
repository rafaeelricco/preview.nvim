local node = require("preview.render.node")

---@type preview.Element
return {
  name = "list",
  lang = "markdown",
  query = [[ (list_item [(list_marker_minus) (list_marker_star) (list_marker_plus) (list_marker_dot) (list_marker_parenthesis)] @marker) @root ]],
  --- Replaces the marker with a depth-chosen bullet; task items conceal the
  --- markers and insert the checkbox icon instead. Ordered numbers remain editable source text.
  ---@param ctx preview.Context
  ---@param m preview.Match
  ---@return preview.Mark[]
  render = function(ctx, m)
    local item, marker = m.root, m.captures.marker[1]
    local row, col, _, ecol = marker:range()
    local task = node.first_child_of_type(item, { "task_list_marker_checked", "task_list_marker_unchecked" })
    local _, _, last, last_col = item:range()
    if last_col == 0 then last = last - 1 end
    local indent = vim.fn.strdisplaywidth(ctx.lines(row):sub(1, ecol))
    if task then
      local icon = task:type() == "task_list_marker_checked" and ctx.config.checkbox.checked or ctx.config.checkbox.unchecked
      local text = icon .. (" "):rep(ctx.config.checkbox.gap)
      indent = vim.fn.strdisplaywidth(ctx.lines(row):sub(1, col)) + vim.fn.strdisplaywidth(text)
    end
    ---@type preview.RowFlow[]
    local flows = {}
    for r = row, last do flows[#flows + 1] = { row = r, kind = "list", indent = indent } end
    if task then
      local tr, tc, _, tec = task:range()
      local checkbox = ctx.config.checkbox
      local icon = task:type() == "task_list_marker_checked" and checkbox.checked or checkbox.unchecked
      local text = icon .. (" "):rep(checkbox.gap)
      -- Swallow the marker's own trailing spaces so the gap is exactly `gap`.
      local content = ctx.lines(row):find("[^ ]", tec + 1) or (tec + 1)
      return {
        { row = row, col = col, opts = { end_col = ecol, conceal = "" } },
        {
          row = tr,
          col = tc,
          opts = { end_col = content - 1, conceal = "", virt_text = { { text, "PreviewCheckbox" } }, virt_text_pos = "inline" },
        },
      }, flows
    end
    if marker:type() == "list_marker_dot" or marker:type() == "list_marker_parenthesis" then
      return {
        { row = row, col = col, opts = { end_col = ecol, hl_group = "PreviewBullet" } },
      }, flows
    end
    local depth = node.count_ancestors(item, "list") -- 1 for top level
    local bullets = ctx.config.list.bullets
    local bullet = bullets[((depth - 1) % #bullets) + 1]
    local gap = ctx.config.list.gap
    local text = bullet .. (" "):rep(gap)
    -- Swallow the marker's own trailing spaces so the gap is exactly `gap`.
    local content = ctx.lines(row):find("[^ ]", ecol + 1) or (ecol + 1)
    local adjustment = vim.fn.strdisplaywidth(text) - (content - 1 - col)
    for _, flow in ipairs(flows) do flow.indent = flow.indent + adjustment end
    return {
      { row = row, col = col, opts = { end_col = content - 1, conceal = "",
        virt_text = { { text, "PreviewBullet" } }, virt_text_pos = "inline" } },
    }, flows
  end,
}
