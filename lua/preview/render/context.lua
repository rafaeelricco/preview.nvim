local layout = require("preview.render.layout")

local M = {}

--- Snapshot for one window redraw. Memoises nvim_buf_get_lines per row.
---@param buf integer
---@param win integer
---@param top integer  0-based inclusive
---@param bot integer  0-based inclusive; clamped to the last line
---@param config preview.Config
---@return preview.Context
function M.new(buf, win, top, bot, config)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local last = math.max(line_count - 1, 0)
  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and info.textoff or 0
  local window_width = math.max(vim.api.nvim_win_get_width(win) - textoff, 1)
  local wrap = vim.wo[win].wrap
  -- Cells a nowrap window is scrolled right; win_col marks are drawn from
  -- window column 0 and must be trimmed to follow the text. virt_lines
  -- scroll natively through virt_lines_overflow = "scroll".
  local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
  local view = vim.tbl_extend("force", config.view, { wrap = wrap }) --[[@as preview.View]]
  local width, left = layout.geometry(window_width, view)
  local tabstop, vartabstop = vim.bo[buf].tabstop, vim.bo[buf].vartabstop

  ---@type table<integer, string>
  local memo = {}

  ---@param row integer
  ---@return string
  local function lines(row)
    local cached = memo[row]
    if cached then
      return cached
    end
    local text = ""
    if row >= 0 and row < line_count then
      text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    end
    memo[row] = text
    return text
  end

  ---@type preview.Context
  local ctx = {
    buf = buf,
    win = win,
    width = width,
    window_width = window_width,
    left = left,
    leftcol = leftcol,
    view = view,
    tabstop = tabstop,
    vartabstop = vartabstop,
    display_signature = table.concat({ tabstop, vartabstop, vim.o.ambiwidth, vim.o.display, tostring(wrap), leftcol }, "|"),
    top = math.max(math.min(top, last), 0),
    bot = math.max(math.min(bot, last), 0),
    tick = vim.b[buf].changedtick,
    lines = lines,
    config = config.render,
  }
  return ctx
end

return M
