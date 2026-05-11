return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        phpactor = {
          cmd = { "phpactor", "language-server" },
          filetypes = { "php" },
          root_dir = vim.loop.cwd(),
          keys = {
            { "<leader>cp", "<cmd>PhpactorContextMenu<cr>", desc = "Phpactor Menu" },
          },
        },
      },
    },
  },
}
