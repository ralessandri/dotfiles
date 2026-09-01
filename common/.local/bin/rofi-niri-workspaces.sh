#!/usr/bin/env bash

workspace_actions=(
  "move-workspace-down"
  "move-workspace-up"
  "move-workspace-to-monitor-left"
  "move-workspace-to-monitor-right"
  "focus-monitor-left"
  "focus-monitor-right"
)

selected=$(
  printf '%s\n' "${workspace_actions[@]}" |
    rofi -dmenu \
      -p "Niri Action" \
      -theme-str "window { width: 300px; }" \
      -theme-str "listview { lines: ${#workspace_actions[@]}; }"
)

# Abbrechen, wenn nichts ausgewählt wurde (z.B. Esc gedrückt)
[ -z "$selected" ] && exit 0

niri msg action "$selected"
