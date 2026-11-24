#!/usr/bin/env bash
set -euo pipefail

# Helpers

_print_usage() {
  printf '%s\n' \
    "Show available Niri workspace, window and monitor-focus actions." \
    "" \
    "Usage: rofi-niri-workspaces.sh [OPTIONS]" \
    "" \
    "Options:" \
    "  --workspaces         Show workspace movement and naming actions" \
    "  --window, --windows  Show window movement actions" \
    "  --focus              Show monitor-focus actions" \
    "  -h, --help           Show this help" \
    "" \
    "Combine filters to show multiple categories. Without filters, show all actions." \
    "Example: rofi-niri-workspaces.sh --workspaces --focus"
}

_available_actions() {
  local outputs workspaces
  outputs=$(niri msg --json outputs)
  workspaces=$(niri msg --json workspaces)

  jq -nr --argjson outputs "${outputs}" --argjson workspaces "${workspaces}" \
    --argjson show_workspaces "${show_workspaces}" \
    --argjson show_window "${show_window}" --argjson show_focus "${show_focus}" '
    def has_content:
      .name != null or .active_window_id != null;
    def center_x:
      .x + (.width / 2 | floor);
    def center_y:
      .y + (.height / 2 | floor);
    def overlaps_x($a; $b):
      $a.x < ($b.x + $b.width) and $b.x < ($a.x + $a.width);
    def overlaps_y($a; $b):
      $a.y < ($b.y + $b.height) and $b.y < ($a.y + $a.height);

    ($workspaces | map(select(.is_focused)) | first) as $focused
    | if $focused == null or $focused.output == null then
        error("No focused workspace available.")
      else . end
    | $outputs[$focused.output].logical as $current
    | if $current == null then
        error("Focused monitor is not active.")
      else . end
    | [$outputs[] | select(.name != $focused.output and .logical != null)
        | .logical] as $others
    | [
        if any($others[];
          (center_x < ($current | center_x)) and overlaps_y(.; $current))
        then "left" else empty end,
        if any($others[];
          (center_x > ($current | center_x)) and overlaps_y(.; $current))
        then "right" else empty end,
        if any($others[];
          (center_y < ($current | center_y)) and overlaps_x(.; $current))
        then "up" else empty end,
        if any($others[];
          (center_y > ($current | center_y)) and overlaps_x(.; $current))
        then "down" else empty end
      ] as $directions
    | [$workspaces[] | select(.output == $focused.output)] as $local
    | ($focused | has_content) as $can_move
    | ($focused.active_window_id != null) as $can_move_window
    | [
        # Swapping with an unnamed empty workspace is undone by niri cleanup.
        if $can_move and any($local[];
          .idx == ($focused.idx + 1) and has_content)
        then "move-workspace-down" else empty end,
        if $can_move and any($local[];
          .idx == ($focused.idx - 1) and has_content)
        then "move-workspace-up" else empty end,
        (if $can_move then $directions[] | "move-workspace-to-monitor-" + .
         else empty end),
        (if $can_move_window then $directions[] | "move-window-to-monitor-" + .
         else empty end),
        if $can_move_window and any($local[]; .idx == ($focused.idx + 1))
        then "move-window-to-workspace-down" else empty end,
        if $can_move_window and any($local[]; .idx == ($focused.idx - 1))
        then "move-window-to-workspace-up" else empty end,
        ($directions[] | "focus-monitor-" + .),
        "set-workspace-name",
        if $focused.name != null then "unset-workspace-name" else empty end
      ]
    | .[]
    | select(
        ($show_workspaces and (startswith("move-workspace-")
          or . == "set-workspace-name" or . == "unset-workspace-name"))
        or ($show_window and startswith("move-window-"))
        or ($show_focus and startswith("focus-monitor-"))
      )
  '
}

_action_label() {
  local action="${1}" direction=""
  case "${action##*-}" in
  left) direction="←" ;;
  right) direction="→" ;;
  up) direction="↑" ;;
  down) direction="↓" ;;
  esac

  case "${action}" in
  move-workspace-up | move-workspace-down)
    printf ' Move workspace %s\n' "${direction}"
    ;;
  move-workspace-to-monitor-*)
    printf ' Move workspace to monitor %s\n' "${direction}"
    ;;
  move-window-to-monitor-*)
    printf ' Move window to monitor %s\n' "${direction}"
    ;;
  move-window-to-workspace-*)
    printf ' Move window to workspace %s\n' "${direction}"
    ;;
  focus-monitor-*)
    printf '◎ Focus monitor %s\n' "${direction}"
    ;;
  set-workspace-name)
    printf '%s\n' " Set workspace name"
    ;;
  unset-workspace-name)
    printf '%s\n' " Clear workspace name"
    ;;
  *)
    printf 'Unsupported menu action: %s\n' "${action}" >&2
    return 1
    ;;
  esac
}

# Workspace naming

_set_workspace_name() {
  local menu_width="${1}"
  local workspace workspace_id current_name workspace_name
  workspace=$(niri msg --json workspaces | jq -ce '.[] | select(.is_focused)')
  workspace_id=$(jq -r '.id' <<<"${workspace}")
  current_name=$(jq -r '.name // ""' <<<"${workspace}")

  if ! workspace_name=$(
    rofi -dmenu -p "Workspace name" -filter "${current_name}" \
      -theme-str "window { width: ${menu_width}ch; }" </dev/null
  ); then
    return 0
  fi

  if [[ -z "${workspace_name//[[:space:]]/}" || "${workspace_name}" == "${current_name}" ]]; then
    return 0
  fi

  # The second prompt must not rename a different workspace after a focus change.
  if ! niri msg --json workspaces |
    jq -e --argjson id "${workspace_id}" 'any(.[]; .is_focused and .id == $id)' >/dev/null; then
    printf '%s\n' "Focused workspace changed; reopen the menu to name it." >&2
    return 1
  fi

  niri msg action set-workspace-name -- "${workspace_name}"
}

# Option parsing

show_workspaces=false
show_window=false
show_focus=false

while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
  -h | --help)
    _print_usage
    exit 0
    ;;
  --workspaces)
    show_workspaces=true
    ;;
  --window | --windows)
    show_window=true
    ;;
  --focus)
    show_focus=true
    ;;
  *)
    printf 'Unknown option: %s\nUse --help to show available options.\n' "${1}" >&2
    exit 2
    ;;
  esac
  shift
done

if [[ "${show_workspaces}" == false && "${show_window}" == false && "${show_focus}" == false ]]; then
  show_workspaces=true
  show_window=true
  show_focus=true
fi

# Prerequisites

for prerequisite in niri rofi jq; do
  if ! command -v "${prerequisite}" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "${prerequisite}" >&2
    exit 1
  fi
done

# Action selection

action_list=$(_available_actions)
if [[ -z "${action_list}" ]]; then
  printf '%s\n' "No actions available for the selected categories."
  exit 0
fi
mapfile -t workspace_actions <<<"${action_list}"

workspace_labels=()
menu_width=36
for action in "${workspace_actions[@]}"; do
  label=$(_action_label "${action}")
  workspace_labels+=("${label}")
  action_width=$((${#label} + 12))
  if [[ "${action_width}" -gt "${menu_width}" ]]; then
    menu_width="${action_width}"
  fi
done

if ! selected_index=$(
  printf '%s\n' "${workspace_labels[@]}" |
    rofi -dmenu -no-custom -no-sort -format i \
      -p "Niri Action" \
      -theme-str "window { width: ${menu_width}ch; }" \
      -theme-str "listview { lines: ${#workspace_actions[@]}; }"
); then
  exit 0
fi

if [[ -z "${selected_index}" ]]; then
  exit 0
fi

selected=""
for action_index in "${!workspace_actions[@]}"; do
  if [[ "${selected_index}" == "${action_index}" ]]; then
    selected="${workspace_actions[action_index]}"
    break
  fi
done
if [[ -z "${selected}" ]]; then
  printf '%s\n' "Invalid menu selection; reopen the menu." >&2
  exit 1
fi

# Command dispatch

# Monitor layout and workspace focus may have changed while the menu was open.
action_list=$(_available_actions)
while IFS= read -r action; do
  if [[ "${selected}" == "${action}" ]]; then
    if [[ "${selected}" == "set-workspace-name" ]]; then
      _set_workspace_name "${menu_width}"
    else
      niri msg action "${selected}"
    fi
    exit 0
  fi
done <<<"${action_list}"

printf '%s\n' "Selected action is no longer available; reopen the menu." >&2
exit 1
