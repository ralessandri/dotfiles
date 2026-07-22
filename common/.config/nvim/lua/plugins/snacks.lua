return {
  {
    "folke/snacks.nvim",
    opts = {
      -- Ensure the git module is active (it is by default, but be explicit).
      git = {},
      picker = {
        sources = {
          explorer = {
            hidden = true,
          },
          files = {
            hidden = true,
          },
          grep = {
            hidden = true,
          },
        },
      },
    },
    init = function()
      local augroup = vim.api.nvim_create_augroup("Typo3PackageGitRoot", { clear = true })

      vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        -- Only trigger for PHP files; other filetypes keep the global cwd
        -- so that tools like PHPActor continue to see the project root.
        pattern = "*.php",
        callback = function(args)
          local bufname = vim.api.nvim_buf_get_name(args.buf)

          -- Skip unnamed buffers and virtual/special buffers (e.g. oil://)
          if bufname == "" or bufname:match("^%w+://") then
            return
          end

          -- Use Snacks.git.get_root() with the buffer path.
          -- This walks up from the file's directory and finds the nearest .git.
          local git_root = Snacks.git.get_root(bufname)

          if not git_root then
            -- No Git repository found for this PHP file; leave cwd unchanged.
            return
          end

          -- lcd: window-local directory change.
          -- Affects git tools (gitsigns, Snacks.picker.git_*, lazygit) that
          -- read the active window's cwd, but does NOT change the global cwd
          -- that PHPActor uses for LSP project-root detection.
          vim.cmd("lcd " .. vim.fn.fnameescape(git_root))
        end,
      })
    end,
  },

  -- gitsigns re-attaches based on the buffer file path, so no extra config
  -- is needed there. The lcd above ensures that picker actions (e.g. git log,
  -- git status) also operate inside the correct extension repository.
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      -- Attach to untracked files so newly created PHP files in an extension
      -- already show gutter signs before the first commit.
      attach_to_untracked = true,
    },
  },
}
