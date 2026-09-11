local M = {}

---@param scope string
---@param msg string
function M.warn_once(scope, msg)
  vim.notify_once(("[preview.nvim:%s] %s"):format(scope, msg), vim.log.levels.WARN)
end

---@param scope string
---@param msg string
function M.error(scope, msg)
  vim.notify(("[preview.nvim:%s] %s"):format(scope, msg), vim.log.levels.ERROR)
end

return M
