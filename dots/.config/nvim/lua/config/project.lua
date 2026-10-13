local M = {}

function M.git_root(bufnr)
  bufnr = bufnr or 0

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].buftype ~= "" or bufname == "" or bufname:match("^%w+://") then
    return nil
  end

  -- The nearest .git marker keeps nested package repositories independent.
  return vim.fs.root(bufname, ".git")
end

return M
