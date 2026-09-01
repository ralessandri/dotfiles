#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/niri-stack-${UID}"
LOCK_FILE="$STATE_DIR/lock"

PROG_NAME="$(basename "$0")"

IPC_SETTLE_DELAY="0.02"
IPC_WAIT_TIMEOUT_MS=750

SCREEN_TRANSITION_DELAY_MS=650

MAIN_WIDTH=""
SECONDARY_WIDTH=""
MAIN_WINDOW="left"
RESTORE_FOCUS="focus-at-restore"

FLATTEN_MAX_ITERATIONS=100

ACTIVE_STATE_FILE=""

# ─────────────────────────────────────────────────────────────
# General helpers
# ─────────────────────────────────────────────────────────────

die() {
  printf '%s: %s\n' "$PROG_NAME" "$*" >&2
  exit 1
}

cleanup_state_on_exit() {
  local exit_code="$?"

  if ((exit_code != 0)) && [[ -n "$ACTIVE_STATE_FILE" ]]; then
    rm -f "$ACTIVE_STATE_FILE" "${ACTIVE_STATE_FILE}.tmp"
  fi
}

trap cleanup_state_on_exit EXIT

print_usage() {
  cat <<EOF
Usage:
  $PROG_NAME toggle [OPTIONS]   Toggle stack mode
  $PROG_NAME stack [OPTIONS]    Activate stack mode
  $PROG_NAME promote            Promote the focused secondary window
  $PROG_NAME restore             Restore the saved layout
  $PROG_NAME status              Show the current layout status

Options:
  -m, --main-width PERCENT      The other width uses the remaining space
  -s, --secondary-width PERCENT The other width uses the remaining space
  -w, --main-window POSITION    left|current|right
  -f, --restore-focus TARGET    focus-at-restore|focus-at-stack|main-at-stack|main-after-promote
  -d, --screen-transition-delay MS
EOF
}

for dependency in niri jq flock; do
  command -v "$dependency" >/dev/null 2>&1 ||
    die "required command not found: $dependency"
done

mkdir -p "$STATE_DIR"
# Runtime directories are normally private already; keep working if their
# permissions cannot be changed in a managed environment.
chmod 700 "$STATE_DIR" 2>/dev/null || true

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

get_focused_context() {
  get_focused_window |
    jq -r '[.workspace_id // empty, .id // empty] | @tsv'
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

niri_act() {
  niri msg action "$@" >/dev/null
  ipc_settle
}

validate_percent() {
  local name="$1"
  local value="$2"

  [[ -z "$value" ]] &&
    return 0

  [[ "$value" =~ ^(100|[1-9][0-9]?)%$ ]] ||
    die "$name must be a percentage between 1% and 100%"
}

validate_options() {
  local main_value
  local secondary_value

  validate_percent "--main-width" "$MAIN_WIDTH"
  validate_percent "--secondary-width" "$SECONDARY_WIDTH"

  if [[ -n "$MAIN_WIDTH" && -n "$SECONDARY_WIDTH" ]]; then
    main_value="${MAIN_WIDTH%%%}"
    secondary_value="${SECONDARY_WIDTH%%%}"

    ((main_value + secondary_value <= 100)) ||
      die "--main-width and --secondary-width must add up to at most 100%"
  fi

  case "$RESTORE_FOCUS" in
  focus-at-restore | focus-at-stack | main-at-stack | main-after-promote)
    ;;
  *)
    die "--restore-focus must be one of: focus-at-restore, focus-at-stack, main-at-stack, main-after-promote"
    ;;
  esac

  case "$MAIN_WINDOW" in
  left | current | right)
    ;;
  *)
    die "--main-window must be one of: left, current, right"
    ;;
  esac

  [[ "$SCREEN_TRANSITION_DELAY_MS" =~ ^[0-9]+$ ]] ||
    die "--screen-transition-delay must be a non-negative integer"
}

resolve_widths() {
  local main_value
  local secondary_value

  if [[ -n "$MAIN_WIDTH" && -z "$SECONDARY_WIDTH" ]]; then
    main_value="${MAIN_WIDTH%%%}"
    secondary_value=$((100 - main_value))

    ((secondary_value > 0)) ||
      die "--main-width leaves no space for the secondary column"

    SECONDARY_WIDTH="${secondary_value}%"
  elif [[ -z "$MAIN_WIDTH" && -n "$SECONDARY_WIDTH" ]]; then
    secondary_value="${SECONDARY_WIDTH%%%}"
    main_value=$((100 - secondary_value))

    ((main_value > 0)) ||
      die "--secondary-width leaves no space for the main column"

    MAIN_WIDTH="${main_value}%"
  fi
}

resolve_main_window() {
  local strategy="$1"
  local focused_id="$2"
  local id

  local -a window_ids

  shift 2
  window_ids=("$@")

  case "$strategy" in
  left)
    printf '%s\n' "${window_ids[0]}"
    ;;
  right)
    printf '%s\n' "${window_ids[${#window_ids[@]} - 1]}"
    ;;
  current)
    for id in "${window_ids[@]}"; do
      if [[ "$id" == "$focused_id" ]]; then
        printf '%s\n' "$id"
        return 0
      fi
    done

    printf '%s\n' "${window_ids[0]}"
    ;;
  esac
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

  niri_act \
    set-column-width \
    "$width"
}

restore_column_widths() {
  local state_file="$1"
  local present_ids="${2:-[]}"

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
    jq -c --argjson present "$present_ids" '
      .windows
      | map(. as $window | select(($present | index($window.id)) != null))
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

    niri_act \
      consume-or-expel-window-right \
      --id "$id"

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

    niri_act \
      move-column-to-last
  done
}

# ─────────────────────────────────────────────────────────────
# Restore validation
# ─────────────────────────────────────────────────────────────

get_present_saved_ids() {
  local workspace_id="$1"
  local state_file="$2"

  get_workspace_windows "$workspace_id" |
    jq -r \
      --slurpfile state "$state_file" \
      '
        ($state[0].windows | map(.id)) as $saved
        | .[]
        | . as $window
        | select(($saved | index($window.id)) != null)
        | .id
      '
}

validate_state_file() {
  local state_file="$1"

  jq -e '
    .version == 1
    and .layout == "column-stack"
    and (.options | type == "object")
    and (.focus | type == "object")
    and (.windows | type == "array" and length >= 2)
    and (([.windows[].id] | unique | length) == (.windows | length))
    and all(.windows[];
      (.id | type == "number")
      and (.column | type == "number")
      and (.row | type == "number")
      and (.tile_size | type == "array")
    )
  ' "$state_file" >/dev/null
}

discard_restore_state() {
  local state_file="$1"

  rm -f "$state_file" "${state_file}.tmp"
  ACTIVE_STATE_FILE=""
  printf '%s: saved layout is no longer restorable; state discarded\n' \
    "$PROG_NAME" >&2
}

# Make only saved windows singleton columns. This is intentionally different
# from flatten_workspace(): new windows may be stacked or positioned anywhere
# and must not be rearranged as a side effect of restoring the old layout.
flatten_saved_workspace() {
  local workspace_id="$1"
  local state_file="$2"
  local windows
  local id
  local iterations=0

  while :; do
    ((iterations++ < FLATTEN_MAX_ITERATIONS)) ||
      die "timed out while separating saved windows"

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

    niri_act \
      consume-or-expel-window-right \
      --id "$id"
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
  local main_id
  local restore_widths
  local context
  local id
  local i

  local -a ids
  local -a ordered_ids

  context="$(get_focused_context)"
  IFS=$'\t' read -r workspace_id focused_id <<<"$context"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  [[ -n "$focused_id" ]] ||
    die "no focused window"

  state_file="$(state_file_for_workspace "$workspace_id")"

  if [[ -e "$state_file" ]]; then
    die "stack mode is already active on this workspace"
  fi

  ACTIVE_STATE_FILE="$state_file"

  windows="$(get_workspace_windows "$workspace_id")"

  mapfile -t ids < <(
    jq -r '.[].id' <<<"$windows"
  )

  if ((${#ids[@]} < 2)); then
    die "at least two tiled windows are required"
  fi

  main_id="$(
    resolve_main_window \
      "$MAIN_WINDOW" \
      "$focused_id" \
      "${ids[@]}"
  )"

  ordered_ids=("$main_id")
  for id in "${ids[@]}"; do
    [[ "$id" == "$main_id" ]] ||
      ordered_ids+=("$id")
  done

  restore_widths=false

  if [[ -n "$MAIN_WIDTH" || -n "$SECONDARY_WIDTH" ]]; then
    restore_widths=true
  fi

  # Save the effective layout options together with the original layout.
  jq \
    --argjson ws "$workspace_id" \
    --argjson focused "$focused_id" \
    --argjson main_id "$main_id" \
    --argjson secondary_id "${ordered_ids[1]}" \
    --arg main_width "$MAIN_WIDTH" \
    --arg secondary_width "$SECONDARY_WIDTH" \
    --arg main_window "$MAIN_WINDOW" \
    --arg restore_focus "$RESTORE_FOCUS" \
    --argjson restore_widths "$restore_widths" \
    '
        {
            version: 1,
            layout: "column-stack",
            workspace_id: $ws,

            options: {
                main_width: ($main_width | if . == "" then null else . end),
                secondary_width: ($secondary_width | if . == "" then null else . end),
                main_window: $main_window,
                restore_widths: $restore_widths,
                restore_focus: $restore_focus
            },

            focus: {
                original_id: $focused,
                initial_main_id: $main_id,
                main_id: $main_id,
                secondary_id: $secondary_id
            },

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
  order_columns "${ordered_ids[@]}"

  # The selected main window is the first column.
  # The next window is the anchor of the secondary stack.
  # All following windows are consumed into that column.
  stack_anchor="${ordered_ids[1]}"

  for ((i = 2; i < ${#ordered_ids[@]}; i++)); do
    focus_window_sync "$stack_anchor"

    niri_act \
      consume-window-into-column
  done

  # Apply the configured column widths.
  if [[ -n "$MAIN_WIDTH" ]]; then
    set_column_width \
      "$main_id" \
      "$MAIN_WIDTH"
  fi

  if [[ -n "$SECONDARY_WIDTH" ]]; then
    set_column_width \
      "$stack_anchor" \
      "$SECONDARY_WIDTH"
  fi

  # Preserve the focus that was active before entering stack mode.
  focus_window_sync "$focused_id"
}

# Swap the focused secondary window with the active main window.
promote_layout() {
  local workspace_id
  local focused_id
  local context
  local state_file
  local main_id
  local main_width
  local secondary_width
  local id
  local i
  local main_index=-1
  local selected_index=-1

  local -a present_ids
  local -a ordered_ids

  context="$(get_focused_context)"
  IFS=$'\t' read -r workspace_id focused_id <<<"$context"

  [[ -n "$workspace_id" && -n "$focused_id" ]] ||
    return 0

  state_file="$(state_file_for_workspace "$workspace_id")"

  [[ -f "$state_file" ]] ||
    return 0

  validate_state_file "$state_file" ||
    return 0

  main_id="$(jq -r '.focus.main_id // empty' "$state_file")"

  [[ -n "$main_id" && "$focused_id" != "$main_id" ]] ||
    return 0

  mapfile -t present_ids < <(
    get_present_saved_ids \
      "$workspace_id" \
      "$state_file"
  )

  for i in "${!present_ids[@]}"; do
    id="${present_ids[$i]}"

    [[ "$id" == "$main_id" ]] &&
      main_index="$i"

    [[ "$id" == "$focused_id" ]] &&
      selected_index="$i"
  done

  ((main_index >= 0 && selected_index >= 0)) ||
    return 0

  start_screen_transition
  ACTIVE_STATE_FILE="$state_file"

  flatten_saved_workspace \
    "$workspace_id" \
    "$state_file"

  mapfile -t present_ids < <(
    get_present_saved_ids \
      "$workspace_id" \
      "$state_file"
  )

  main_index=-1
  selected_index=-1

  for i in "${!present_ids[@]}"; do
    id="${present_ids[$i]}"

    [[ "$id" == "$main_id" ]] &&
      main_index="$i"

    [[ "$id" == "$focused_id" ]] &&
      selected_index="$i"
  done

  ((main_index >= 0 && selected_index >= 0)) ||
    die "main or selected window disappeared during promotion"

  ordered_ids=("${present_ids[@]}")
  ordered_ids[$main_index]="$focused_id"
  ordered_ids[$selected_index]="$main_id"

  order_columns "${ordered_ids[@]}"

  for ((i = 2; i < ${#ordered_ids[@]}; i++)); do
    focus_window_sync "${ordered_ids[1]}"
    niri_act consume-window-into-column
  done

  main_width="$(jq -r '.options.main_width // empty' "$state_file")"
  secondary_width="$(jq -r '.options.secondary_width // empty' "$state_file")"

  if [[ -n "$main_width" ]]; then
    set_column_width \
      "${ordered_ids[0]}" \
      "$main_width"
  fi

  if [[ -n "$secondary_width" ]]; then
    set_column_width \
      "${ordered_ids[1]}" \
      "$secondary_width"
  fi

  focus_window_sync "${ordered_ids[0]}"

  jq \
    --argjson main_id "${ordered_ids[0]}" \
    --argjson secondary_id "${ordered_ids[1]}" \
    '.focus.main_id = $main_id
     | .focus.secondary_id = $secondary_id' \
    "$state_file" \
    >"${state_file}.tmp"

  chmod 600 "${state_file}.tmp"
  mv "${state_file}.tmp" "$state_file"

  ACTIVE_STATE_FILE=""
}

# ─────────────────────────────────────────────────────────────
# Restore layout
# ─────────────────────────────────────────────────────────────

restore_layout() {
  local workspace_id="${1:-}"
  local restore_focus_id="${2:-}"
  local state_file
  local restore_widths
  local context
  local focus_strategy
  local present_ids_json

  local column_json
  local anchor
  local count
  local i

  local -a all_ids
  local -a present_ids
  local -a focus_candidates

  if [[ -z "$workspace_id" || -z "$restore_focus_id" ]]; then
    context="$(get_focused_context)"
    IFS=$'\t' read -r workspace_id restore_focus_id <<<"$context"
  fi

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  [[ -n "$restore_focus_id" ]] ||
    die "no focused window"

  state_file="$(state_file_for_workspace "$workspace_id")"

  [[ -f "$state_file" ]] ||
    die "no saved layout for this workspace"

  ACTIVE_STATE_FILE="$state_file"

  if ! validate_state_file "$state_file"; then
    discard_restore_state "$state_file"
    return 0
  fi

  mapfile -t present_ids < <(
    get_present_saved_ids \
      "$workspace_id" \
      "$state_file"
  )

  if ((${#present_ids[@]} == 0)); then
    discard_restore_state "$state_file"
    return 0
  fi

  restore_widths="$(
    jq -r \
      '.options.restore_widths // false' \
      "$state_file"
  )"

  # Convert only the saved windows back into singleton columns. Additional
  # windows remain where they are, including any columns they share.
  flatten_saved_workspace \
    "$workspace_id" \
    "$state_file"

  # A window can disappear while the multi-step IPC sequence is running.
  # Continue with the remaining saved windows when possible.
  mapfile -t present_ids < <(
    get_present_saved_ids \
      "$workspace_id" \
      "$state_file"
  )

  if ((${#present_ids[@]} == 0)); then
    discard_restore_state "$state_file"
    return 0
  fi

  present_ids_json="$(
    printf '%s\n' "${present_ids[@]}" |
      jq -Rsc '
        split("\n")
        | map(select(length > 0) | tonumber)
      '
  )"

  # Restore the original flattened left-to-right order.
  mapfile -t all_ids < <(
    jq -r --argjson present "$present_ids_json" '
            .windows
      | map(. as $window | select(($present | index($window.id)) != null))
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

      niri_act \
        consume-window-into-column
    done

  done < <(
    jq -c --argjson present "$present_ids_json" '
            .windows
            | map(. as $window | select(($present | index($window.id)) != null))
            | sort_by(.column, .row)
            | group_by(.column)
            | .[]
        ' "$state_file"
  )

  # Restore the original column widths when the stack changed them.
  if [[ "$restore_widths" == "true" ]]; then
    restore_column_widths \
      "$state_file" \
      "$present_ids_json"
  fi

  focus_strategy="$(jq -r '.options.restore_focus // "focus-at-restore"' "$state_file")"

  case "$focus_strategy" in
  focus-at-restore)
    focus_candidates=("$restore_focus_id")
    ;;
  focus-at-stack)
    focus_candidates=(
      "$(jq -r '.focus.original_id // empty' "$state_file")"
    )
    ;;
  main-at-stack)
    focus_candidates=(
      "$(jq -r '.focus.initial_main_id // .focus.main_id // empty' "$state_file")"
    )
    ;;
  main-after-promote)
    focus_candidates=(
      "$(jq -r '.focus.main_id // empty' "$state_file")"
    )
    ;;
  esac

  # Fall back to the current focus, then main, then the first saved window.
  focus_candidates+=(
    "$restore_focus_id"
    "$(jq -r '.focus.main_id // empty' "$state_file")"
  )
  focus_candidates+=("${all_ids[@]}")

  for restore_focus_id in "${focus_candidates[@]}"; do
    [[ -n "$restore_focus_id" ]] ||
      continue

    if get_windows | jq -e --arg id "$restore_focus_id" \
      'any(.[]; (.id | tostring) == $id)' >/dev/null; then
      focus_window_sync "$restore_focus_id"
      break
    fi
  done

  rm -f "$state_file" "${state_file}.tmp"
  ACTIVE_STATE_FILE=""
}

# ─────────────────────────────────────────────────────────────
# Status
# ─────────────────────────────────────────────────────────────

status_layout() {
  local workspace_id
  local state_file
  local main_width
  local secondary_width
  local restore_focus

  workspace_id="$(get_workspace_id)"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  state_file="$(state_file_for_workspace "$workspace_id")"

  if [[ ! -f "$state_file" ]]; then
    printf 'normal\n'
    return
  fi

  main_width="$(
    jq -r \
      '.options.main_width // "auto"' \
      "$state_file"
  )"

  secondary_width="$(
    jq -r \
      '.options.secondary_width // "auto"' \
      "$state_file"
  )"

  restore_focus="$(
    jq -r \
      '.options.restore_focus // "focus-at-restore"' \
      "$state_file"
  )"

  printf 'stacked (main: %s, secondary: %s, restore-focus: %s)\n' \
    "$main_width" \
    "$secondary_width" \
    "$restore_focus"
}

# ─────────────────────────────────────────────────────────────
# Toggle
# ─────────────────────────────────────────────────────────────

toggle_layout() {
  local workspace_id
  local focused_id
  local context
  local state_file

  context="$(get_focused_context)"
  IFS=$'\t' read -r workspace_id focused_id <<<"$context"

  [[ -n "$workspace_id" ]] ||
    die "no focused workspace"

  state_file="$(state_file_for_workspace "$workspace_id")"

  # Freeze the visible output while the multi-step layout
  # transformation happens in the background.
  start_screen_transition

  if [[ -f "$state_file" ]]; then
    restore_layout "$workspace_id" "$focused_id"
  else
    stack_layout
  fi
}

# ─────────────────────────────────────────────────────────────
# CLI options
# ─────────────────────────────────────────────────────────────

COMMAND="${1:-toggle}"

shift || true

if [[ "$COMMAND" == "--help" || "$COMMAND" == "-h" ]]; then
  print_usage
  exit 0
fi

while (($# > 0)); do
  case "$1" in

  --main-width | -m)
    (($# >= 2)) ||
      die "missing value for $1"
    MAIN_WIDTH="$2"
    shift
    ;;

  --secondary-width | -s)
    (($# >= 2)) ||
      die "missing value for $1"
    SECONDARY_WIDTH="$2"
    shift
    ;;

  --main-window | -w)
    (($# >= 2)) ||
      die "missing value for $1"
    MAIN_WINDOW="$2"
    shift
    ;;

  --restore-focus | -f)
    (($# >= 2)) ||
      die "missing value for $1"
    RESTORE_FOCUS="$2"
    shift
    ;;

  --screen-transition-delay | -d)
    (($# >= 2)) ||
      die "missing value for $1"
    SCREEN_TRANSITION_DELAY_MS="$2"
    shift
    ;;

  --help | -h)
    print_usage
    exit 0
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

validate_options
resolve_widths

exec 9>"$LOCK_FILE"
flock -n 9 ||
  die "another niri-stack operation is already running"

# ─────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────

case "$COMMAND" in

stack)
  start_screen_transition
  stack_layout
  ;;

promote)
  promote_layout
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
  print_usage >&2
  exit 2
  ;;

esac
