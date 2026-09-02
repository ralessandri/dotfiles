#!/usr/bin/env bash

set -euo pipefail

umask 077

# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/niri-stack-${UID}"
LOCK_FILE="$STATE_DIR/lock"

PROG_NAME="$(basename "$0")"

IPC_SETTLE_DELAY="0.02"
IPC_WAIT_TIMEOUT_MS=750
FOCUS_POLL_INTERVAL_SECONDS="0.01"
FOCUS_POLL_INCREMENT_MS=10

SCREEN_TRANSITION_DELAY_MS=650

MAIN_WIDTH=""
SECONDARY_WIDTH=""
MAIN_WINDOW="left"
RESTORE_FOCUS="focus-at-restore"

FLATTEN_MAX_ITERATIONS=100
STATE_VERSION=1

# Set while a state transition is in progress so interrupted operations do
# not leave a state file describing a partial layout.
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

write_state_file() {
  local state_file="$1"
  local temporary_file="${state_file}.tmp"

  cat >"$temporary_file"
  chmod 600 "$temporary_file"
  mv "$temporary_file" "$state_file"
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
  if ! niri msg action "$@" >/dev/null; then
    die "niri action failed: $*"
  fi

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

    sleep "$FOCUS_POLL_INTERVAL_SECONDS"
    elapsed=$((elapsed + FOCUS_POLL_INCREMENT_MS))
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

save_stack_state() {
  local state_file="$1"
  local workspace_id="$2"
  local focused_id="$3"
  local main_id="$4"
  local secondary_id="$5"
  local main_window="$6"
  local restore_focus="$7"
  local restore_widths="$8"
  local windows="$9"

  jq \
    --argjson ws "$workspace_id" \
    --argjson focused "$focused_id" \
    --argjson main_id "$main_id" \
    --argjson secondary_id "$secondary_id" \
    --arg main_width "$MAIN_WIDTH" \
    --arg secondary_width "$SECONDARY_WIDTH" \
    --arg main_window "$main_window" \
    --arg restore_focus "$restore_focus" \
    --argjson version "$STATE_VERSION" \
    --argjson restore_widths "$restore_widths" \
    '
        {
            version: $version,
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
    | write_state_file "$state_file"
}

build_stack_from_singleton_columns() {
  local stack_anchor
  local i
  local -a ordered_ids

  ordered_ids=("$@")
  stack_anchor="${ordered_ids[1]}"

  order_columns "${ordered_ids[@]}"

  for ((i = 2; i < ${#ordered_ids[@]}; i++)); do
    focus_window_sync "$stack_anchor"
    niri_act consume-window-into-column
  done
}

apply_stack_geometry() {
  local workspace_id="$1"
  shift
  local -a ordered_ids=("$@")

  flatten_workspace "$workspace_id"
  build_stack_from_singleton_columns "${ordered_ids[@]}"
}

apply_stack_widths() {
  local main_id="$1"
  local secondary_id="$2"
  local main_width="$3"
  local secondary_width="$4"

  if [[ -n "$main_width" ]]; then
    set_column_width "$main_id" "$main_width"
  fi

  if [[ -n "$secondary_width" ]]; then
    set_column_width "$secondary_id" "$secondary_width"
  fi
}

get_state_window_ids() {
  local state_file="$1"
  local present_ids="$2"

  jq -r --argjson present "$present_ids" '
    .windows
    | map(. as $window | select(($present | index($window.id)) != null))
    | sort_by(.column, .row)
    | .[].id
  ' "$state_file"
}

get_state_columns() {
  local state_file="$1"
  local present_ids="$2"

  jq -c --argjson present "$present_ids" '
    .windows
    | map(. as $window | select(($present | index($window.id)) != null))
    | sort_by(.column, .row)
    | group_by(.column)
    | .[]
  ' "$state_file"
}

rebuild_columns_from_state() {
  local state_file="$1"
  local present_ids="$2"
  local column_json
  local anchor
  local count
  local i
  local -a ordered_ids

  mapfile -t ordered_ids < <(
    get_state_window_ids "$state_file" "$present_ids"
  )

  order_columns "${ordered_ids[@]}"

  while IFS= read -r column_json; do
    anchor="$(jq -r '.[0].id' <<<"$column_json")"
    count="$(jq 'length' <<<"$column_json")"

    for ((i = 1; i < count; i++)); do
      focus_window_sync "$anchor"
      niri_act consume-window-into-column
    done
  done < <(
    get_state_columns "$state_file" "$present_ids"
  )
}

apply_focus_strategy() {
  local state_file="$1"
  local restore_focus_id="$2"
  local focus_strategy
  local candidate

  local -a focus_candidates
  local -a saved_ids=("${@:3}")

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

  # Use safe fallbacks when the requested focus target is no longer present.
  focus_candidates+=(
    "$restore_focus_id"
    "$(jq -r '.focus.main_id // empty' "$state_file")"
    "${saved_ids[@]}"
  )

  for candidate in "${focus_candidates[@]}"; do
    [[ -n "$candidate" ]] ||
      continue

    if get_windows | jq -e --arg id "$candidate" \
      'any(.[]; (.id | tostring) == $id)' >/dev/null; then
      focus_window_sync "$candidate"
      return 0
    fi
  done

  return 0
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

find_id_index() {
  local target_id="$1"
  local id
  local index=0

  shift
  for id in "$@"; do
    if [[ "$id" == "$target_id" ]]; then
      printf '%s\n' "$index"
      return 0
    fi

    index=$((index + 1))
  done

  return 1
}

update_active_stack_roles() {
  local state_file="$1"
  local main_id="$2"
  local secondary_id="$3"

  jq \
    --argjson main_id "$main_id" \
    --argjson secondary_id "$secondary_id" \
    '.focus.main_id = $main_id
     | .focus.secondary_id = $secondary_id' \
    "$state_file" \
    | write_state_file "$state_file"
}

validate_state_file() {
  local state_file="$1"

  jq -e --argjson version "$STATE_VERSION" '
    .version == $version
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
  local main_id
  local restore_widths
  local context
  local id

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

  # Keep the state registered until all stack phases complete successfully.
  ACTIVE_STATE_FILE="$state_file"

  # Capture the current tiled windows and resolve their stack roles.
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

  # Persist the original layout before changing any window geometry.
  save_stack_state \
    "$state_file" \
    "$workspace_id" \
    "$focused_id" \
    "$main_id" \
    "${ordered_ids[1]}" \
    "$MAIN_WINDOW" \
    "$RESTORE_FOCUS" \
    "$restore_widths" \
    "$windows"

  # Normalize columns and build the main-plus-secondary stack.
  apply_stack_geometry \
    "$workspace_id" \
    "${ordered_ids[@]}"

  # Apply configured column widths, then restore the pre-stack focus.
  apply_stack_widths \
    "$main_id" \
    "${ordered_ids[1]}" \
    "$MAIN_WIDTH" \
    "$SECONDARY_WIDTH"

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
  local main_index=-1
  local selected_index=-1

  local -a present_ids
  local -a ordered_ids

  context="$(get_focused_context)"
  IFS=$'\t' read -r workspace_id focused_id <<<"$context"

  [[ -n "$workspace_id" && -n "$focused_id" ]] ||
    return 0

  state_file="$(state_file_for_workspace "$workspace_id")"

  # Promotion is intentionally a silent no-op outside an active stack.
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

  main_index="$(find_id_index "$main_id" "${present_ids[@]}" 2>/dev/null || true)"
  selected_index="$(find_id_index "$focused_id" "${present_ids[@]}" 2>/dev/null || true)"

  [[ -n "$main_index" && -n "$selected_index" ]] ||
    return 0

  start_screen_transition
  # Keep the state registered until every promotion phase completes.
  ACTIVE_STATE_FILE="$state_file"

  flatten_saved_workspace \
    "$workspace_id" \
    "$state_file"

  mapfile -t present_ids < <(
    get_present_saved_ids \
      "$workspace_id" \
      "$state_file"
  )

  main_index="$(find_id_index "$main_id" "${present_ids[@]}" 2>/dev/null || true)"
  selected_index="$(find_id_index "$focused_id" "${present_ids[@]}" 2>/dev/null || true)"

  [[ -n "$main_index" && -n "$selected_index" ]] ||
    die "main or selected window disappeared during promotion"

  ordered_ids=("${present_ids[@]}")
  ordered_ids[$main_index]="$focused_id"
  ordered_ids[$selected_index]="$main_id"

  build_stack_from_singleton_columns "${ordered_ids[@]}"

  main_width="$(jq -r '.options.main_width // empty' "$state_file")"
  secondary_width="$(jq -r '.options.secondary_width // empty' "$state_file")"

  apply_stack_widths \
    "${ordered_ids[0]}" \
    "${ordered_ids[1]}" \
    "$main_width" \
    "$secondary_width"

  focus_window_sync "${ordered_ids[0]}"

  update_active_stack_roles \
    "$state_file" \
    "${ordered_ids[0]}" \
    "${ordered_ids[1]}"

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
  local present_ids_json

  local -a all_ids
  local -a present_ids

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

  # Keep the state registered until the original layout is fully restored.
  ACTIVE_STATE_FILE="$state_file"

  if ! validate_state_file "$state_file"; then
    discard_restore_state "$state_file"
    return 0
  fi

  # Identify saved windows that still exist on the focused workspace.
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

  # Separate only the saved windows into singleton columns. Additional
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

  # Restore the original column order and grouping.
  mapfile -t all_ids < <(
    get_state_window_ids "$state_file" "$present_ids_json"
  )
  rebuild_columns_from_state "$state_file" "$present_ids_json"

  # Restore the original column widths when the stack changed them.
  if [[ "$restore_widths" == "true" ]]; then
    restore_column_widths \
      "$state_file" \
      "$present_ids_json"
  fi

  apply_focus_strategy \
    "$state_file" \
    "$restore_focus_id" \
    "${all_ids[@]}"

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

  # Keep status side-effect free when the saved state is invalid.
  if ! validate_state_file "$state_file" 2>/dev/null; then
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
