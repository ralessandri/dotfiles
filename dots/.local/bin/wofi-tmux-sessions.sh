#!/usr/bin/env bash
#
# Interactively pick, create, or switch to a tmux session via wofi.
#
# - If run from inside an existing tmux client, switches to the chosen
#   session (creating it first if it does not exist yet).
# - If run outside tmux (e.g. bound to a WM keybinding), launches a
#   terminal emulator that attaches to (or creates) the session, since
#   tmux itself requires a controlling TTY.
#
# Requirements: tmux, wofi, a terminal emulator (configurable via $TERMINAL).

set -Eeuo pipefail
IFS=$'\n\t'

# --- Configuration -----------------------------------------------------

readonly WOFI_PROMPT="tmux session"
# Terminal emulators to try, in order, if $TERMINAL is not set/available.
readonly FALLBACK_TERMINALS=(alacritty ghostty kitty wezterm foot)

# --- Logging helpers -----------------------------------------------------

log_error() {
  # Print a message to stderr.
  printf 'tmux-session-picker: %s\n' "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

# --- Preconditions -----------------------------------------------------

require_cmd() {
  # Abort with a clear message if a required command is missing.
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
}

# --- Core logic -----------------------------------------------------

get_sessions() {
  # Print existing tmux session names, one per line.
  # stderr is suppressed because tmux exits non-zero when no server is
  # running yet, which is an expected state, not an error here.
  tmux list-sessions -F '#S' 2>/dev/null || true
}

pick_session() {
  # Show a wofi dmenu with existing sessions (or an empty prompt if none
  # exist yet) and print the user's selection.
  local sessions=$1
  local line_count

  if [[ -n "$sessions" ]]; then
    line_count=$(printf '%s\n' "$sessions" | grep -c '^')
    printf '%s\n' "$sessions" | wofi --show dmenu -L "$line_count" -p "$WOFI_PROMPT"
  else
    # No sessions yet: still let the user type a name to create one.
    wofi --show dmenu -L 1 -p "new $WOFI_PROMPT"
  fi
}

find_terminal() {
  # Print the terminal emulator to use, or return 1 if none is available.
  local term="${TERMINAL:-}"

  if [[ -n "$term" ]] && command -v "$term" >/dev/null 2>&1; then
    printf '%s\n' "$term"
    return 0
  fi

  local candidate
  for candidate in "${FALLBACK_TERMINALS[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

attach_inside_tmux() {
  # Switch the current tmux client to the given session, creating it
  # first if it doesn't exist.
  local session=$1

  tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session"
  tmux switch-client -t "$session"
}

attach_outside_tmux() {
  # Launch a terminal emulator running tmux, attaching to (or creating)
  # the session. This is needed because tmux requires a TTY, which is
  # not available when this script is invoked from a WM keybinding.
  local session=$1
  local term

  if ! term=$(find_terminal); then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "tmux-session-picker" "No terminal emulator found. Set \$TERMINAL."
    fi
    die "no terminal emulator found; set \$terminal to override auto-detection"
  fi

  "$term" -e tmux new-session -A -s "$session"
}

main() {
  require_cmd tmux
  require_cmd wofi

  local sessions selected

  sessions=$(get_sessions)
  selected=$(pick_session "$sessions")

  # User cancelled the picker (Esc / empty selection).
  [[ -z "$selected" ]] && exit 0

  if [[ -n "${TMUX:-}" ]]; then
    attach_inside_tmux "$selected"
  else
    attach_outside_tmux "$selected"
  fi
}

main "$@"
