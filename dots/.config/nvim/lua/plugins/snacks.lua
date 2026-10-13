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
            layout = {
              -- auto_hide = { "input" },
            },
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
        callback = function(args)
          -- Scope cwd-based Git tools to the repository containing the active file.
          local git_root = require("config.project").git_root(args.buf)
          if not git_root and vim.bo[args.buf].buftype ~= "" then
            return
          end

          local cwd = git_root or vim.fn.getcwd(-1, -1)

          -- Keep Git tools on the active repository without changing Neovim's global cwd.
          vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
        end,
      })
    end,
  },

  -- gitsigns re-attaches based on the buffer file path, so no extra config
  -- is needed there. The window-local cwd keeps cwd-based Git actions in the
  -- repository containing the active file.
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      -- Attach to untracked files so newly created PHP files in an extension
      -- already show gutter signs before the first commit.
      attach_to_untracked = true,
    },
  },
}
