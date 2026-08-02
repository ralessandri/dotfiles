local wezterm = require("wezterm")
local act = wezterm.action
local config = {}

config.color_scheme = "Catppuccin Macchiato"
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 11.0
config.hide_tab_bar_if_only_one_tab = true

config.colors = {
  background = "#282c34",
}

config.leader = {
  key = "s",
  mods = "CTRL",
  timeout_milliseconds = 1000,
}

config.keys = {
  {
    key = "r",
    mods = "LEADER",
    action = act.ReloadConfiguration,
  },

  {
    key = "p",
    mods = "LEADER",
    action = act.PasteFrom("Clipboard"),
  },
  -------------------------------------------------------------------
  -- Splits
  -------------------------------------------------------------------
  {
    key = "h",
    mods = "LEADER",
    action = act.SplitHorizontal({
      domain = "CurrentPaneDomain",
    }),
  },

  {
    key = "v",
    mods = "LEADER",
    action = act.SplitVertical({
      domain = "CurrentPaneDomain",
    }),
  },

  {
    key = "RightArrow",
    mods = "CTRL|SHIFT",
    action = act.SplitHorizontal({
      domain = "CurrentPaneDomain",
    }),
  },

  {
    key = "DownArrow",
    mods = "CTRL|SHIFT",
    action = act.SplitVertical({
      domain = "CurrentPaneDomain",
    }),
  },
  -------------------------------------------------------------------
  -- New tab
  -------------------------------------------------------------------

  {
    key = "c",
    mods = "LEADER",
    action = act.SpawnTab("CurrentPaneDomain"),
  },

  -------------------------------------------------------------------
  -- Zoom pane
  -------------------------------------------------------------------

  {
    key = "Enter",
    mods = "CTRL|SHIFT",
    action = act.TogglePaneZoomState,
  },

  -------------------------------------------------------------------
  -- Pane navigation
  -------------------------------------------------------------------

  {
    key = "LeftArrow",
    mods = "ALT",
    action = act.ActivatePaneDirection("Left"),
  },

  {
    key = "RightArrow",
    mods = "ALT",
    action = act.ActivatePaneDirection("Right"),
  },

  {
    key = "UpArrow",
    mods = "ALT",
    action = act.ActivatePaneDirection("Up"),
  },

  {
    key = "DownArrow",
    mods = "ALT",
    action = act.ActivatePaneDirection("Down"),
  },

  {
    key = "w",
    mods = "CTRL|SHIFT", -- or CTRL|SHIFT
    action = wezterm.action.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }),
  },

  {
    key = "n",
    mods = "CTRL|SHIFT",
    action = act.PromptInputLine({
      description = "Workspace name:",
      action = wezterm.action_callback(function(window, pane, line)
        if line and #line > 0 then
          window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
        end
      end),
    }),
  },
}

table.insert(config.keys, {
  key = "i",
  mods = "LEADER",
  action = wezterm.action_callback(function(window, pane)
    local workspace = window:active_workspace()
    window:toast_notification("WezTerm", "Workspace: " .. workspace, nil, 2000)
  end),
})

return config
