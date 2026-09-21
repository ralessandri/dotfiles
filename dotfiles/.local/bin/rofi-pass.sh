#!/usr/bin/env bash

set -euo pipefail

STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
CLIP_TIME=45

# Check required commands
for cmd in pass rofi wl-copy wl-paste; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing command: %s\n' "$cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$STORE" ]]; then
  printf 'Password store not found: %s\n' "$STORE" >&2
  exit 1
fi

# Read a metadata field
_get_field() {
  local entry="$1"
  local field="$2"

  pass show "$entry" |
    sed -n "s/^${field}:[[:space:]]*//p" |
    head -n 1
}

# Copy text and clear it after the timeout
_copy_temporary() {
  local value="$1"

  [[ -n "$value" ]] || return 1

  printf '%s' "$value" | wl-copy

  (
    sleep "$CLIP_TIME"

    current="$(wl-paste --no-newline 2>/dev/null || true)"

    if [[ "$current" == "$value" ]]; then
      wl-copy --clear
    fi
  ) >/dev/null 2>&1 &
}

# Show a missing field notification
_notify_missing() {
  local field="$1"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "pass" "Field '$field' not found"
  fi
}

# List password store entries
entries="$(
  find "$STORE" -type f -name '*.gpg' -printf '%P\n' |
    sed 's/\.gpg$//' |
    sort
)"

[[ -n "$entries" ]] || exit 0

# Select an entry
status=0
entry="$(
  printf '%s\n' "$entries" |
    rofi \
      -dmenu \
      -i \
      -p 'pass' \
      -kb-custom-1 'Alt+Return'
)" || status=$?

[[ $status -eq 1 ]] && exit 0
[[ -n "$entry" ]] || exit 0

# Copy the password on Enter
if [[ $status -eq 0 ]]; then
  pass -c "$entry"
  exit $?
fi

# Open the action menu on Alt+Enter
if [[ $status -eq 10 ]]; then
  action="$(
    printf '%s\n' \
      'Copy username' \
      'Copy email' \
      'Open URL' \
      'Show entry' \
      'Edit entry' |
      rofi -dmenu -i -p "$entry"
  )" || exit 0

  [[ -n "$action" ]] || exit 0

  case "$action" in
  'Copy username')
    value="$(_get_field "$entry" username)"

    if [[ -n "$value" ]]; then
      _copy_temporary "$value"
    else
      _notify_missing "username"
    fi
    ;;

  'Copy email')
    value="$(_get_field "$entry" email)"

    if [[ -n "$value" ]]; then
      _copy_temporary "$value"
    else
      _notify_missing "email"
    fi
    ;;

  'Open URL')
    value="$(_get_field "$entry" url)"

    if [[ -n "$value" ]]; then
      xdg-open "$value" >/dev/null 2>&1 &
    else
      _notify_missing "url"
    fi
    ;;

  'Show entry')
    pass show "$entry" |
      rofi -dmenu -p "$entry"
    ;;

  'Edit entry')
    pass edit "$entry"
    ;;
  esac
fi
