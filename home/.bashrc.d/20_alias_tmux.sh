alias tm='tm.sh'

# --- Shortcuts (frequently used, kept short) ---
tma() { tmsa "$@"; }
tmn() { tmsn "$@"; }

alias tml='tmux list-sessions'

# alias tmks='tmux kill-session -t'
alias tmksall='tmux kill-session -a'

tmsa() {
  if ! command -v gum &>/dev/null; then
    echo "Error: gum is not installed. See https://github.com/charmbracelet/gum" >&2
    return 1
  fi

  local sessions session_count selected session_name

  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  if [[ -z "$sessions" ]]; then
    # No sessions exist
    if gum confirm "No tmux sessions found. Create a new one?"; then
      session_name=$(gum input --placeholder "Session name (leave empty for default)")
      tmux new-session ${session_name:+-s "$session_name"}
    else
      return 1
    fi
    return
  fi

  session_count=$(wc -l <<<"$sessions")

  if [[ "$session_count" -eq 1 ]]; then
    # Exactly one session exists
    tmux attach-session -t "$sessions"
  else
    # Multiple sessions exist
    selected=$(gum choose --header "Select a tmux session" <<<"$sessions")
    [[ -n "$selected" ]] && tmux attach-session -t "$selected"
  fi
}

tmsn() {
  if ! command -v gum &>/dev/null; then
    echo "Error: gum is not installed. See https://github.com/charmbracelet/gum" >&2
    return 1
  fi

  local session_name="$1"

  # No name passed as argument -> ask interactively
  if [[ -z "$session_name" ]]; then
    session_name=$(gum input --placeholder "Session name (leave empty for default)")
  fi

  # Session with that name already exists -> offer to attach instead
  if [[ -n "$session_name" ]] && tmux has-session -t "$session_name" 2>/dev/null; then
    if gum confirm "Session '$session_name' already exists. Attach instead?"; then
      tmux attach-session -t "$session_name"
    fi
    return
  fi

  tmux new-session ${session_name:+-s "$session_name"}
}

tmsk() {
  if ! command -v gum &>/dev/null; then
    echo "Error: gum is not installed. See https://github.com/charmbracelet/gum" >&2
    return 1
  fi

  local sessions session_count selected

  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  if [[ -z "$sessions" ]]; then
    gum style --foreground 3 "No tmux sessions to kill."
    return 0
  fi

  session_count=$(wc -l <<<"$sessions")

  if [[ "$session_count" -eq 1 ]]; then
    # Exactly one session exists
    if gum confirm "Kill session '$sessions'?"; then
      tmux kill-session -t "$sessions"
    fi
    return
  fi

  # Multiple sessions exist -> allow multi-select
  selected=$(gum choose --no-limit \
    --header "Select session(s) to kill (space to mark, enter to confirm)" \
    <<<"$sessions")

  if [[ -z "$selected" ]]; then
    return 0
  fi

  if gum confirm "Kill $(wc -l <<<"$selected") session(s)?"; then
    while IFS= read -r session; do
      tmux kill-session -t "$session"
    done <<<"$selected"
  fi
}
