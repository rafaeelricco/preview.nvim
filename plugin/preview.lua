if vim.fn.has("nvim-0.12") ~= 1 then
  vim.notify_once("preview.nvim requires Neovim >= 0.12 (decoration provider on_range)", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_preview then
  return
end
vim.g.loaded_preview = 1

if vim.g.preview_auto_setup then
  vim.defer_fn(function()
    require("preview").setup(vim.g.preview_auto_setup)
  end, 0)
end
