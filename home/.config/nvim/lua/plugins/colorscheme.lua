return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "macchiato",
      transparent_background = true,
      float = {
        transparent = true,
        -- solid = true,
      },
      color_overrides = {
        macchiato = {
          -- base = "#242424", -- Haupt-Hintergrundfarbe (Normal bg)
          -- mantle = "#2B2B2B", -- etwas dunklerer Hintergrund (z. B. Sidebars)
          -- crust = "#0f0f1c", -- dunkelster Hintergrund (z. B. Statusline-Ecken)
        },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-macchiato",
    },
  },
}
