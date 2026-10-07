return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "macchiato",
      transparent_background = true,
      float = {
        transparent = true,
        -- solid = true, -- Use opaque backgrounds for floating windows.
      },
    },
  },
  {
    "AvengeMedia/base46",
    lazy = true,
    opts = {
      transparency = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dms",
    },
  },
}
