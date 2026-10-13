return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        phpactor = {
          cmd = { "phpactor", "language-server" },
          filetypes = { "php" },
          root_dir = function(bufnr, on_dir)
            local bufname = type(bufnr) == "number" and vim.api.nvim_buf_get_name(bufnr) or bufnr
            -- The TYPO3 project's composer.lock identifies its workspace above package extensions.
            local root_dir = bufname ~= "" and vim.fs.root(bufname, "composer.lock") or nil

            if type(on_dir) == "function" then
              on_dir(root_dir)
            else
              return root_dir
            end
          end,
        },
      },
    },
  },
}
