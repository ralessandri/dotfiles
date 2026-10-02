#!/usr/bin/env bash

set -euo pipefail

# Configuration

FLOATING_WIDTH="900"
FLOATING_HEIGHT="600"
CENTER_FLOATING_WINDOW=false
IPC_SETTLE_DELAY="0.05"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/niri-toggle-floating-${UID}"

# Helpers

_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Toggle the focused Niri window between tiling and floating.

Options:
  -w, --width PIXELS           Floating window width (default: $FLOATING_WIDTH)
  -H, --height PIXELS          Floating window height (default: $FLOATING_HEIGHT)
  -n, --no-center              Do not center a window when it becomes floating
  -h, --help                   Show this help message

Example:
  $(basename "$0") --width 1200 --height 800
EOF
}

validate_size() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[1-9][0-9]*%?$ ]] ||
    _die "$name must be a positive pixel value or percentage"
}

_niri_action() {
  niri msg action "$@"
  sleep "$IPC_SETTLE_DELAY"
}

_state_file_for_window() {
  local window_id="$1"

  printf '%s/window-%s.width\n' "$STATE_DIR" "$window_id"
}

_save_tiling_width() {
  local window_id="$1"
  local width="$2"
  local state_file
  local temporary_file

  [[ "$width" =~ ^[1-9][0-9]*$ ]] ||
    _die "could not determine the tiled window width"

  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR" 2>/dev/null || true

  state_file="$(_state_file_for_window "$window_id")"
  temporary_file="$(mktemp "${STATE_DIR}/.window-${window_id}.XXXXXX")"

  printf '%s\n' "$width" >"$temporary_file"
  chmod 600 "$temporary_file"
  mv "$temporary_file" "$state_file"
}

_saved_tiling_width() {
  local window_id="$1"
  local state_file
  local width

  state_file="$(_state_file_for_window "$window_id")"
  [[ -f "$state_file" ]] || return 1

  width="$(<"$state_file")"
  [[ "$width" =~ ^[1-9][0-9]*$ ]] ||
    _die "invalid saved tiled window width: $state_file"

  printf '%s\n' "$width"
}

# Option parsing

while (($# > 0)); do
  case "$1" in
  -w | --width)
    (($# >= 2)) || _die "missing value for $1"
    FLOATING_WIDTH="$2"
    shift 2
    ;;
  -H | --height)
    (($# >= 2)) || _die "missing value for $1"
    FLOATING_HEIGHT="$2"
    shift 2
    ;;
  -n | --no-center)
    CENTER_FLOATING_WINDOW=false
    shift
    ;;
  -h | --help)
    print_usage
    exit 0
    ;;
  *)
    _die "unknown option: $1"
    ;;
  esac
done

validate_size "--width" "$FLOATING_WIDTH"
validate_size "--height" "$FLOATING_HEIGHT"

for dependency in niri jq; do
  command -v "$dependency" >/dev/null 2>&1 ||
    _die "required command not found: $dependency"
done

# Window layout

focused_window="$(niri msg --json focused-window)"
window_id="$(jq -r '.id // empty' <<<"$focused_window")"
is_floating="$(jq -r '.is_floating' <<<"$focused_window")"

[[ "$window_id" =~ ^[1-9][0-9]*$ ]] || _die "could not determine the focused window ID"
[[ "$is_floating" == "true" || "$is_floating" == "false" ]] ||
  _die "could not determine whether the focused window is floating"

if [[ "$is_floating" == "true" ]]; then
  _niri_action move-window-to-tiling --id "$window_id"
  if tiling_width="$(_saved_tiling_width "$window_id")"; then
    _niri_action set-window-width --id "$window_id" "$tiling_width"
  fi
  _niri_action reset-window-height --id "$window_id"
else
  has_floating_state=false
  if _saved_tiling_width "$window_id" >/dev/null; then
    has_floating_state=true
  fi

  tiling_width="$(jq -r '.layout.tile_size[0] | round' <<<"$focused_window")"
  _niri_action move-window-to-floating --id "$window_id"
  _save_tiling_width "$window_id" "$tiling_width"

  if [[ "$has_floating_state" == false ]]; then
    _niri_action set-window-width --id "$window_id" "$FLOATING_WIDTH"
    _niri_action set-window-height --id "$window_id" "$FLOATING_HEIGHT"

    if [[ "$CENTER_FLOATING_WINDOW" == true ]]; then
      _niri_action center-window --id "$window_id"
    fi
  fi
fi
