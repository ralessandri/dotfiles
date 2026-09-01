#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/niri-stack-${UID}"

IPC_SETTLE_DELAY="0.02"
IPC_WAIT_TIMEOUT_MS=750

SCREEN_TRANSITION_DELAY_MS=650

SPLIT_MAIN_WIDTH="75%"
SPLIT_STACK_WIDTH="25%"

USE_SPLIT=false

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# General helpers
# ─────────────────────────────────────────────────────────────

die() {
  printf 'niri-stack: %s\n' "$*" >&2
  exit 1
}

ipc_settle() {
  sleep "$IPC_SETTLE_DELAY"
}

get_focused_window() {
  niri msg --json focused-window
}

get_windows() {
  niri msg --json windows
}

get_workspace_id() {
  get_focused_window |
    jq -r '.workspace_id // empty'
}

get_focused_id() {
  get_focused_window |
    jq -r '.id // empty'
}

state_file_for_workspace() {
  local workspace_id="$1"

  printf '%s/workspace-%s.json\n' \
    "$STATE_DIR" \
    "$workspace_id"
}

start_screen_transition() {
  niri msg action \
    do-screen-transition \
    --delay-ms "$SCREEN_TRANSITION_DELAY_MS" \
    >/dev/null 2>&1 ||
    true
}

# ─────────────────────────────────────────────────────────────
# Focus synchronization
# ─────────────────────────────────────────────────────────────

wait_for_focus() {
  local expected_id="$1"

  local elapsed=0
  local current_id

  while ((elapsed < IPC_WAIT_TIMEOUT_MS)); do
    current_id="$(
      get_focused_id 2>/dev/null ||
        true
    )"

    if [[ "$current_id" == "$expected_id" ]]; then
      return 0
    fi

    sleep 0.01
    elapsed=$((elapsed + 10))
  done

  return 1
}

focus_window_sync() {
  local id="$1"

  niri msg action \
    focus-window \
    --id "$id" \
    >/dev/null

  wait_for_focus "$id" ||
    die "timed out waiting for window $id to receive focus"
}

# ─────────────────────────────────────────────────────────────
# Workspace windows
# ─────────────────────────────────────────────────────────────

get_workspace_windows() {
  local workspace_id="$1"

  get_windows |
    jq \
      --argjson ws "$workspace_id" \
      '
            [
                .[]
                | select(
                    .workspace_id == $ws
                    and
                    .layout.pos_in_scrolling_layout != null
                )
            ]
            | sort_by(
                .layout.pos_in_scrolling_layout[0],
                .layout.pos_in_scrolling_layout[1]
            )
            '
}

# ─────────────────────────────────────────────────────────────
# Column width
# ─────────────────────────────────────────────────────────────

set_column_width() {
  local id="$1"
  local width="$2"

  focus_window_sync "$id"

  niri msg action \
    set-column-width \
    "$width" \
    >/dev/null

  ipc_settle
}

restore_column_widths() {
  local state_file="$1"

  local column_json
  local anchor
  local width

  while IFS= read -r column_json; do
    anchor="$(
      jq -r '.[0].id // empty' \
        <<<"$column_json"
    )"

    width="$(
      jq -r '.[0].tile_size[0] | round' \
        <<<"$column_json"
    )"

    [[ -n "$anchor" ]] ||
      continue

    [[ -n "$width" ]] ||
      continue

    set_column_width \
      "$anchor" \
      "$width"

  done < <(
    jq -c '
      .windows
      | sort_by(.column, .row)
      | group_by(.column)
      | .[]
    ' "$state_file"
  )
}

# ─────────────────────────────────────────────────────────────
# Normalize layout
# ─────────────────────────────────────────────────────────────

flatten_workspace() {
  local workspace_id="$1"

  local windows
  local id

  windows="$(get_workspace_windows "$workspace_id")"

  # Process columns from right to left.
  #
  # For every multi-window column, expel all windows except
  # the first one. Processing bottom-to-top keeps the original
  # visual order stable.
  while IFS= read -r id; do
    [[ -n "$id" ]] ||
      continue

    niri msg action \
      consume-or-expel-window-right \
      --id "$id" \
      >/dev/null

    ipc_settle

  done < <(
    jq -r '
            sort_by(
                .layout.pos_in_scrolling_layout[0],
                .layout.pos_in_scrolling_layout[1]
            )

            | group_by(
                .layout.pos_in_scrolling_layout[0]
            )

            | reverse
            | .[]

            | select(length > 1)

            | .[1:]
            | reverse
            | .[]

            | .id
        ' <<<"$windows"
  )
}

# ─────────────────────────────────────────────────────────────
# Order singleton columns
# ─────────────────────────────────────────────────────────────

order_columns() {
  local id

  for id in "$@"; do
    focus_window_sync "$id"

    niri msg action \
      move-column-to-last \
      >/dev/null

    ipc_settle
  done
}

# ─────────────────────────────────────────────────────────────
# Restore validation
# ─────────────────────────────────────────────────────────────

validate_restore_state() {
  local workspace_id="$1"
  local state_file="$2"

  local saved
  local current

  saved="$(
    jq -r \
      '.windows[].id' \
      "$state_file" |
      sort
  )"

  current="$(
    get_workspace_windows "$workspace_id" |
      jq -r '.[].id' |
      sort
  )"

  # The saved windows must all still be present, but windows opened after
  # entering stack mode are deliberately not part of this comparison.
  if [[ -n "$(comm -23 \
    <(printf '%s\n' "$saved") \
    <(printf '%s\n' "$current")
  )" ]]; then
    return 1
  fi
}

discard_restore_state() {
  local state_file="$1"

  rm -f "$state_file"
  printf 'niri-stack: saved layout is no longer restorable; state discarded\n' >&2
}

# Make only saved windows singleton columns. This is intentionally different
# from flatten_workspace(): new windows may be stacked or positioned anywhere
# and must not be rearranged as a side effect of restoring the old layout.
flatten_saved_workspace() {
  local workspace_id="$1"
  local state_file="$2"
  local windows
  local id

  while :; do
    windows="$(get_workspace_windows "$workspace_id")"

    id="$(
      jq -r \
        --slurpfile state "$state_file" \
        '
          ($state[0].windows | map(.id)) as $saved
          | [
              .[]
              | . as $window
              | select(($saved | index($window.id)) != null)
            ]
          | sort_by(.layout.pos_in_scrolling_layout[0])
          | group_by(.layout.pos_in_scrolling_layout[0])
          | map(select(length > 1) | .[-1].id)
          | .[0] // empty
        ' \
        <<<"$windows"
    )"

    [[ -n "$id" ]] ||
      break

    niri msg action \
      consume-or-expel-window-right \
      --id "$id" \
      >/dev/null

    ipc_settle
  done
}

# ─────────────────────────────────────────────────────────────
# Stack layout
# ─────────────────────────────────────────────────────────────

stack_layout() {
  local workspace_id
  local focused_id
  local state_file
  local windows
  local stack_anchor
  local split_json
  local i

  local -a ids

  workspace_id="$(get_workspace_id)"
  focused_id="$(get_focused_id)"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  [[ -n "$focused_id" ]] ||
    die "no focused window"

  state_file="$(state_file_for_workspace "$workspace_id")"

  if [[ -e "$state_file" ]]; then
    die "stack mode is already active on this workspace"
  fi

  windows="$(get_workspace_windows "$workspace_id")"

  mapfile -t ids < <(
    jq -r '.[].id' <<<"$windows"
  )

  if ((${#ids[@]} < 2)); then
    die "at least two tiled windows are required"
  fi

  # Store whether this stack uses the fixed 2/3 + 1/3 split.
  if [[ "$USE_SPLIT" == true ]]; then
    split_json=true
  else
    split_json=false
  fi

  # Save the complete original layout state before changing it.
  jq \
    --argjson ws "$workspace_id" \
    --argjson focused "$focused_id" \
    --argjson split "$split_json" \
    '
        {
            workspace_id: $ws,
            focused_id: $focused,
            split: $split,

            windows: [
                .[]
                | {
                    id: .id,
                    column: .layout.pos_in_scrolling_layout[0],
                    row: .layout.pos_in_scrolling_layout[1],
                    tile_size: .layout.tile_size
                }
            ]
        }
        ' \
    <<<"$windows" \
    >"${state_file}.tmp"

  chmod 600 "${state_file}.tmp"

  mv \
    "${state_file}.tmp" \
    "$state_file"

  # Turn every tiled window into a singleton column.
  flatten_workspace "$workspace_id"

  # Restore the exact flattened left-to-right order.
  order_columns "${ids[@]}"

  # The first window remains the main window.
  #
  # The second window is the anchor of the secondary stack.
  # All following windows are consumed into that column.
  stack_anchor="${ids[1]}"

  for ((i = 2; i < ${#ids[@]}; i++)); do
    focus_window_sync "$stack_anchor"

    niri msg action \
      consume-window-into-column \
      >/dev/null

    ipc_settle
  done

  # Apply the optional fixed horizontal split.
  if [[ "$USE_SPLIT" == true ]]; then
    set_column_width \
      "${ids[0]}" \
      "$SPLIT_MAIN_WIDTH"

    set_column_width \
      "$stack_anchor" \
      "$SPLIT_STACK_WIDTH"
  fi

  # Preserve the focus that was active before entering stack mode.
  focus_window_sync "$focused_id"
}

# ─────────────────────────────────────────────────────────────
# Restore layout
# ─────────────────────────────────────────────────────────────

restore_layout() {
  local workspace_id
  local restore_focus_id
  local state_file
  local split_enabled

  local column_json
  local anchor
  local count
  local i

  local -a all_ids

  workspace_id="$(get_workspace_id)"

  # Preserve whichever window is currently selected inside the
  # stack and return focus to it after the original layout has
  # been reconstructed.
  restore_focus_id="$(get_focused_id)"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  [[ -n "$restore_focus_id" ]] ||
    die "no focused window"

  state_file="$(state_file_for_workspace "$workspace_id")"

  [[ -f "$state_file" ]] ||
    die "no saved layout for this workspace"

  if ! validate_restore_state \
    "$workspace_id" \
    "$state_file"; then
    discard_restore_state "$state_file"
    return 0
  fi

  split_enabled="$(
    jq -r \
      '.split // false' \
      "$state_file"
  )"

  # Convert only the saved windows back into singleton columns. Additional
  # windows remain where they are, including any columns they share.
  flatten_saved_workspace \
    "$workspace_id" \
    "$state_file"

  # A window can disappear while the multi-step IPC sequence is running.
  # Do not leave a stale state file behind in that case either.
  if ! validate_restore_state \
    "$workspace_id" \
    "$state_file"; then
    discard_restore_state "$state_file"
    return 0
  fi

  # Restore the original flattened left-to-right order.
  mapfile -t all_ids < <(
    jq -r '
            .windows
            | sort_by(.column, .row)
            | .[].id
        ' "$state_file"
  )

  order_columns "${all_ids[@]}"

  # Rebuild all original multi-window columns.
  while IFS= read -r column_json; do
    anchor="$(
      jq -r \
        '.[0].id' \
        <<<"$column_json"
    )"

    count="$(
      jq \
        'length' \
        <<<"$column_json"
    )"

    for ((i = 1; i < count; i++)); do
      focus_window_sync "$anchor"

      niri msg action \
        consume-window-into-column \
        >/dev/null

      ipc_settle
    done

  done < <(
    jq -c '
            .windows
            | sort_by(.column, .row)
            | group_by(.column)
            | .[]
        ' "$state_file"
  )

  # Restore the original column widths only when the temporary
  # stack was created with --split.
  if [[ "$split_enabled" == "true" ]]; then
    restore_column_widths "$state_file"
  fi

  # Return focus to the window selected while stack mode was active.
  focus_window_sync "$restore_focus_id"

  rm -f "$state_file"
}

# ─────────────────────────────────────────────────────────────
# Status
# ─────────────────────────────────────────────────────────────

status_layout() {
  local workspace_id
  local state_file
  local split_enabled

  workspace_id="$(get_workspace_id)"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  state_file="$(state_file_for_workspace "$workspace_id")"

  if [[ ! -f "$state_file" ]]; then
    printf 'normal\n'
    return
  fi

  split_enabled="$(
    jq -r \
      '.split // false' \
      "$state_file"
  )"

  if [[ "$split_enabled" == "true" ]]; then
    printf 'stacked (split)\n'
  else
    printf 'stacked\n'
  fi
}

# ─────────────────────────────────────────────────────────────
# Toggle
# ─────────────────────────────────────────────────────────────

toggle_layout() {
  local workspace_id
  local state_file

  workspace_id="$(get_workspace_id)"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  state_file="$(state_file_for_workspace "$workspace_id")"

  # Freeze the visible output while the multi-step layout
  # transformation happens in the background.
  start_screen_transition

  if [[ -f "$state_file" ]]; then
    restore_layout
  else
    stack_layout
  fi
}

# ─────────────────────────────────────────────────────────────
# CLI options
# ─────────────────────────────────────────────────────────────

COMMAND="${1:-toggle}"

shift || true

while (($# > 0)); do
  case "$1" in

  --split | -s)
    USE_SPLIT=true
    ;;

  --)
    shift
    break
    ;;

  *)
    die "unknown option: $1"
    ;;

  esac

  shift
done

# ─────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────

case "$COMMAND" in

stack)
  start_screen_transition
  stack_layout
  ;;

restore)
  start_screen_transition
  restore_layout
  ;;

toggle)
  toggle_layout
  ;;

status)
  status_layout
  ;;

*)
  cat >&2 <<EOF
Usage:
  $(basename "$0") toggle [--split|-s]
  $(basename "$0") stack [--split|-s]
  $(basename "$0") restore
  $(basename "$0") status
EOF
  exit 2
  ;;

esac
