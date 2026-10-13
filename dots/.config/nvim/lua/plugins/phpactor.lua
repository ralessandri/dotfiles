return {
  {
    "phpactor/phpactor",
    ft = "php",
    build = "composer install --no-dev -o",
    keys = {
      { "<leader>cp", "<cmd>PhpactorContextMenu<cr>", desc = "Phpactor Menu" },
      { "<leader>ci", "<cmd>PhpactorImportClass<cr>", desc = "Import Class" },
    },
  },
}
