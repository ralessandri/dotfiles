-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--vim.g.lazyvim_php_lsp = "intelephense"
--vim.lsp.set_log_level("debug")

vim.g.lazyvim_prettier_needs_config = false

vim.opt.list = true
vim.opt.listchars = {
  space = "·",
  tab = "→ ",
  trail = "·",
}

-- LazyVim.root.git = function()
--   local buf = vim.api.nvim_get_current_buf()
--   local path = LazyVim.root.bufpath(buf) or vim.uv.cwd()
--   return vim.fs.root(path, ".git") or LazyVim.root.get()
-- end
