#!/usr/bin/env bash

workspace_actions=(
  "move-workspace-to-monitor-left"
  "move-workspace-to-monitor-right"
  "move-workspace-to-monitor-up"
  "move-workspace-to-monitor-down"
  "focus-monitor-left"
  "focus-monitor-right"
  "move-workspace-down"
  "move-workspace-up"
)

selected=$(printf '%s\n' "${workspace_actions[@]}" | wofi --dmenu --prompt "Niri Action")

# Abbrechen, wenn nichts ausgewählt wurde (z.B. Esc gedrückt)
[ -z "$selected" ] && exit 0

niri msg action "$selected"
