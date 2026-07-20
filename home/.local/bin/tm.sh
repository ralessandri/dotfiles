#!/usr/bin/env bash
#
# tm - Interactive tmux session manager built on top of gum.
#
# Consolidates the previously separate tmsa/tmsn/tmsk/tml/tmksall
# functions and aliases into a single script with subcommands.
#
# Usage:
# tm <command> [arguments]
#
# Install:
# 1. Save this file as e.g. ~/bin/tm
# 2. chmod +x ~/bin/tm
# 3. Make sure ~/bin is in your $PATH
#
# Optional shortcuts in .bashrc/.zshrc:
# alias tma='tm attach'
# alias tmn='tm new'
# alias tmk='tm kill'
# alias tml='tm list'
#
# Dependencies:
# tmux (required), gum (required for interactive prompts),
# zoxide (required for 'sessionizer')
set -uo pipefail
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="1.4.0"

# ---------------------------------------------------------------------------
# Catppuccin Macchiato colors
# https://github.com/catppuccin/catppuccin
# ---------------------------------------------------------------------------
readonly CTP_ROSEWATER="#f4dbd6"
readonly CTP_FLAMINGO="#f0c6c6"
readonly CTP_PINK="#f5bde6"
readonly CTP_MAUVE="#c6a0f6"
readonly CTP_RED="#ed8796"
readonly CTP_MAROON="#ee99a0"
readonly CTP_PEACH="#f5a97f"
readonly CTP_YELLOW="#eed49f"
readonly CTP_GREEN="#a6da95"
readonly CTP_TEAL="#8bd5ca"
readonly CTP_SKY="#91d7e3"
readonly CTP_SAPPHIRE="#7dc4e4"
readonly CTP_BLUE="#8aadf4"
readonly CTP_LAVENDER="#b7bdf8"
readonly CTP_TEXT="#cad3f5"
readonly CTP_SUBTEXT1="#b8c0e0"
readonly CTP_SUBTEXT0="#a5adcb"
readonly CTP_OVERLAY2="#939ab7"
readonly CTP_OVERLAY1="#8087a2"
readonly CTP_OVERLAY0="#6e738d"
readonly CTP_SURFACE2="#5b6078"
readonly CTP_SURFACE1="#494d64"
readonly CTP_SURFACE0="#363a4f"
readonly CTP_BASE="#24273a"
readonly CTP_MANTLE="#1e2030"
readonly CTP_CRUST="#181926"

readonly COLOR_WARN="$CTP_YELLOW"
readonly COLOR_ERROR="$CTP_RED"

# gum reads these GUM_* environment variables as defaults for every
# invocation of the respective subcommand, so all prompts across the
# script get a consistent Catppuccin Macchiato theme without having
# to pass --foreground/--background flags individually everywhere.
export GUM_CONFIRM_PROMPT_FOREGROUND="$CTP_TEXT"
export GUM_CONFIRM_SELECTED_FOREGROUND="$CTP_BASE"
export GUM_CONFIRM_SELECTED_BACKGROUND="$CTP_MAUVE"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$CTP_SUBTEXT0"
export GUM_CONFIRM_UNSELECTED_BACKGROUND="$CTP_SURFACE0"

export GUM_CHOOSE_CURSOR_FOREGROUND="$CTP_MAUVE"
export GUM_CHOOSE_SELECTED_FOREGROUND="$CTP_GREEN"
export GUM_CHOOSE_HEADER_FOREGROUND="$CTP_BLUE"
export GUM_CHOOSE_ITEM_FOREGROUND="$CTP_TEXT"

export GUM_INPUT_CURSOR_FOREGROUND="$CTP_MAUVE"
export GUM_INPUT_PROMPT_FOREGROUND="$CTP_BLUE"
export GUM_INPUT_PLACEHOLDER_FOREGROUND="$CTP_OVERLAY0"

export GUM_FILTER_INDICATOR_FOREGROUND="$CTP_MAUVE"
export GUM_FILTER_MATCH_FOREGROUND="$CTP_PEACH"
export GUM_FILTER_PROMPT_FOREGROUND="$CTP_BLUE"
export GUM_FILTER_HEADER_FOREGROUND="$CTP_BLUE"
export GUM_FILTER_TEXT_FOREGROUND="$CTP_TEXT"
export GUM_FILTER_CURSOR_TEXT_FOREGROUND="$CTP_GREEN"

export GUM_SPIN_SPINNER_FOREGROUND="$CTP_MAUVE"
export GUM_SPIN_TITLE_FOREGROUND="$CTP_TEXT"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_err() {
  if command -v gum &>/dev/null; then
    gum style --foreground "$COLOR_ERROR" "Error: $*" >&2
  else
    printf 'Error: %s\n' "$*" >&2
  fi
}
_warn() {
  if command -v gum &>/dev/null; then
    gum style --foreground "$COLOR_WARN" "$*"
  else
    printf '%s\n' "$*"
  fi
}
_require_gum() {
  if ! command -v gum &>/dev/null; then
    _err "gum is not installed. See https://github.com/charmbracelet/gum"
    return 1
  fi
}
_require_tmux() {
  if ! command -v tmux &>/dev/null; then
    _err "tmux is not installed."
    return 1
  fi
}
_require_zoxide() {
  if ! command -v zoxide &>/dev/null; then
    _err "zoxide is not installed. See https://github.com/ajeetdsouza/zoxide"
    return 1
  fi
}
_require_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    _err "This command requires an interactive terminal."
    return 1
  fi
}
_list_sessions() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null
}
_attach_to_session() {
  local target="$1"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$target"
  else
    tmux attach-session -t "$target"
  fi
}
_new_session() {
  local name="${1:-}" start_dir="${2:-}"
  local -a opts=()
  [[ -n "$name" ]] && opts+=(-s "$name")
  [[ -n "$start_dir" ]] && opts+=(-c "$start_dir")
  if [[ -n "${TMUX:-}" ]]; then
    tmux new-session -d "${opts[@]}"
    local target="${name:-$(tmux list-sessions -F '#{session_name}' | tail -n1)}"
    _attach_to_session "$target"
  else
    tmux new-session "${opts[@]}"
  fi
}
# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <command> [options]
Commands:
  attach, a [name]     Attach to a tmux session
  new, n [name]        Create a new tmux session
  kill, k [name] [-f]  Kill session(s)
  kill-all, ka [-f]    Kill all sessions except current
  list, l, ls          List tmux sessions
  sessionizer, s       zoxide-powered session picker
  --version, -v        Show version
  help, -h, --help     Show this help
Use '${SCRIPT_NAME} --help <command>' for detailed help.
EOF
}
_usage_command() {
  case "$1" in
  attach | a)
    cat <<EOF
Usage: ${SCRIPT_NAME} attach|a [session-name]
If no session name is given:
- One session  → auto-attach
- Multiple     → interactive picker
- None         → offer to create new
EOF
    ;;
  new | n)
    cat <<EOF
Usage: ${SCRIPT_NAME} new|n [session-name]
Creates a new tmux session. If the name already exists, offers to attach instead.
EOF
    ;;
  kill | k)
    cat <<EOF
Usage: ${SCRIPT_NAME} kill|k [session-name] [-f|--force]
If no name is given → interactive multi-select.
-f, --force skips confirmation.
EOF
    ;;
  kill-all | ka)
    cat <<EOF
Usage: ${SCRIPT_NAME} kill-all|ka [-f|--force]
Kills all sessions except the current one.
-f, --force skips confirmation.
EOF
    ;;
  list | l | ls)
    cat <<EOF
Usage: ${SCRIPT_NAME} list|l|ls
Shows tmux sessions with name, window count, attached status and creation time.
EOF
    ;;
  sessionizer | s)
    cat <<EOF
Usage: ${SCRIPT_NAME} sessionizer|s
Fuzzy selects from zoxide directory history and creates/attaches a named session.
EOF
    ;;
  *)
    _usage
    ;;
  esac
}
# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_attach() {
  _require_tmux || return 1
  local target="${1:-}" sessions session_count selected session_name
  if [[ -n "$target" ]]; then
    if tmux has-session -t "$target" 2>/dev/null; then
      _attach_to_session "$target"
      return
    fi
    _require_gum && _require_tty || return 1
    if gum confirm "Session '$target' not found. Create it?"; then
      _new_session "$target"
    fi
    return
  fi
  _require_gum && _require_tty || return 1
  sessions=$(_list_sessions)
  if [[ -z "$sessions" ]]; then
    if gum confirm "No tmux sessions found. Create a new one?"; then
      session_name=$(gum input --placeholder "Session name (leave empty for default)")
      _new_session "$session_name"
    fi
    return
  fi
  session_count=$(wc -l <<<"$sessions")
  if [[ "$session_count" -eq 1 ]]; then
    _attach_to_session "$sessions"
  else
    selected=$(gum choose --header "Select a tmux session" <<<"$sessions")
    [[ -n "$selected" ]] && _attach_to_session "$selected"
  fi
}
cmd_new() {
  _require_tmux || return 1
  local session_name="${1:-}"
  if [[ -z "$session_name" ]]; then
    _require_gum && _require_tty || return 1
    session_name=$(gum input --placeholder "Session name (leave empty for default)")
  fi
  if [[ -n "$session_name" ]] && tmux has-session -t "$session_name" 2>/dev/null; then
    _require_gum && _require_tty || return 1
    if gum confirm "Session '$session_name' already exists. Attach instead?"; then
      _attach_to_session "$session_name"
    fi
    return
  fi
  _new_session "$session_name"
}
cmd_kill() {
  _require_tmux || return 1
  local force=false target="" opt
  # Use getopts for proper option handling
  while getopts ":f-:" opt; do
    case "${opt}" in
    f) force=true ;;
    -)
      case "${OPTARG}" in
      force) force=true ;;
      *)
        _err "Unknown option --${OPTARG}"
        return 1
        ;;
      esac
      ;;
    *)
      _err "Unknown option"
      return 1
      ;;
    esac
  done
  shift $((OPTIND - 1))
  target="${1:-}"
  # ... (rest of cmd_kill remains functionally the same)
  if [[ -n "$target" ]]; then
    if ! tmux has-session -t "$target" 2>/dev/null; then
      _err "Session '$target' not found."
      return 1
    fi
    if [[ "$force" == true ]] || { _require_gum && _require_tty && gum confirm "Kill session '$target'?"; }; then
      tmux kill-session -t "$target"
    fi
    return
  fi
  # Interactive kill (unchanged logic, just cleaner option parsing)
  local sessions=$(_list_sessions)
  if [[ -z "$sessions" ]]; then
    _warn "No tmux sessions to kill."
    return 0
  fi
  _require_gum && _require_tty || return 1
  local selected
  selected=$(gum choose --no-limit \
    --header "Select session(s) to kill (space to mark, enter to confirm)" \
    <<<"$sessions")
  if [[ -n "$selected" ]] && { [[ "$force" == true ]] || gum confirm "Kill $(wc -l <<<"$selected") session(s)?"; }; then
    while IFS= read -r session; do
      tmux kill-session -t "$session"
    done <<<"$selected"
  fi
}
cmd_kill_all() {
  _require_tmux || return 1
  local force=false opt
  while getopts ":f-:" opt; do
    case "${opt}" in
    f) force=true ;;
    -)
      case "${OPTARG}" in
      force) force=true ;;
      *)
        _err "Unknown option --${OPTARG}"
        return 1
        ;;
      esac
      ;;
    *)
      _err "Unknown option"
      return 1
      ;;
    esac
  done
  local sessions=$(_list_sessions)
  if [[ -z "$sessions" ]]; then
    _warn "No tmux sessions to kill."
    return 0
  fi
  if [[ "$force" == true ]] || { _require_gum && _require_tty && gum confirm "Kill all sessions except the current one? ($(wc -l <<<"$sessions") total)"; }; then
    tmux kill-session -a
  fi
}
cmd_list() {
  _require_tmux || return 1
  # ... (unchanged - good as is)
  local raw
  raw=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{?session_attached,yes,no}|#{t:session_created}' 2>/dev/null)
  if [[ -z "$raw" ]]; then
    _warn "No tmux sessions running."
    return 0
  fi
  local name windows attached created
  local name_width=4 windows_width=7 attached_width=8
  while IFS='|' read -r name windows attached created; do
    ((${#name} > name_width)) && name_width=${#name}
    ((${#windows} > windows_width)) && windows_width=${#windows}
    ((${#attached} > attached_width)) && attached_width=${#attached}
  done <<<"$raw"
  printf '%-*s %-*s %-*s %s\n' \
    "$name_width" "NAME" "$windows_width" "WINDOWS" "$attached_width" "ATTACHED" "CREATED"
  while IFS='|' read -r name windows attached created; do
    printf '%-*s %-*s %-*s %s\n' \
      "$name_width" "$name" "$windows_width" "$windows" "$attached_width" "$attached" "$created"
  done <<<"$raw"
}
cmd_sessionizer() {
  _require_gum && _require_tmux && _require_zoxide && _require_tty || return 1
  # ... (unchanged)
  local candidates selected session_name dir existing_path
  candidates=$(zoxide query -l 2>/dev/null)
  if [[ -z "$candidates" ]]; then
    _err "zoxide has no tracked directories yet."
    return 1
  fi
  candidates=$(while IFS= read -r dir; do [[ -d "$dir" ]] && printf '%s\n' "$dir"; done <<<"$candidates")
  [[ -z "$candidates" ]] && {
    _err "No existing directories in zoxide database."
    return 1
  }
  selected=$(gum filter --placeholder "Select a project directory" <<<"$candidates")
  [[ -z "$selected" ]] && return 0
  session_name=$(basename "$selected" | tr '.:' '__')
  if tmux has-session -t "$session_name" 2>/dev/null; then
    existing_path=$(tmux display-message -p -t "$session_name" '#{pane_current_path}' 2>/dev/null)
    if [[ "$existing_path" == "$selected" ]]; then
      _attach_to_session "$session_name"
      return
    fi
    _warn "A different session named '$session_name' already exists."
    session_name=$(gum input --placeholder "Enter a different session name" --value "${session_name}-2")
    [[ -z "$session_name" ]] && return 1
  fi
  _new_session "$session_name" "$selected"
}
# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
  attach | a) cmd_attach "$@" ;;
  new | n) cmd_new "$@" ;;
  kill | k) cmd_kill "$@" ;;
  kill-all | ka) cmd_kill_all "$@" ;;
  list | l | ls) cmd_list "$@" ;;
  sessionizer | s) cmd_sessionizer "$@" ;;
  --version | -v)
    printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
    ;;
  help | -h | --help)
    if [[ -n "${1:-}" ]]; then
      _usage_command "$1"
    else
      _usage
    fi
    ;;
  *)
    _err "Unknown command '$cmd'"
    _usage
    return 1
    ;;
  esac
}
main "$@"
