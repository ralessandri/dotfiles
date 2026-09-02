#!/usr/bin/env bash

set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NIRI_DIR="${CONFIG_HOME}/niri"

ACTIONS_FILE="${NIRI_DIR}/actions.kdl"
ACTIONS_DIR="${NIRI_DIR}/actions"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/niri-action-manager-${UID}"
LOCK_FILE="${RUNTIME_DIR}/actions.lock"

RELOAD_DELAY="0.05"

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true

mkdir -p "$ACTIONS_DIR"

if [[ ! -e "$ACTIONS_FILE" ]]; then
  cat >"$ACTIONS_FILE" <<'EOF'
// Managed by niri-action-manager.sh.
// Do not add persistent configuration here.
EOF
fi

die() {
  printf 'niri-action-manager: %s\n' "$*" >&2
  exit 1
}

normalize_name() {
  local name="$1"

  name="${name%.kdl}"

  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "invalid action name: $name"

  printf '%s\n' "$name"
}

action_file() {
  printf '%s/%s.kdl\n' "$ACTIONS_DIR" "$1"
}

include_line() {
  printf 'include "actions/%s.kdl"' "$1"
}

action_exists() {
  [[ -f "$(action_file "$1")" ]]
}

action_enabled() {
  local name="$1"
  local line

  line="$(include_line "$name")"

  grep -Fxq "$line" "$ACTIONS_FILE"
}

get_enabled_actions() {
  sed -nE \
    's|^[[:space:]]*include[[:space:]]+"actions/([A-Za-z0-9._-]+)\.kdl"[[:space:]]*$|\1|p' \
    "$ACTIONS_FILE" |
    sort -u
}

write_actions() {
  local tmp
  local name

  tmp="$(mktemp "${NIRI_DIR}/.actions.kdl.XXXXXX")"

  {
    printf '%s\n' \
      '// Managed by niri-action-manager.sh.' \
      '// Do not add persistent configuration here.'

    for name in "$@"; do
      printf 'include "actions/%s.kdl"\n' "$name"
    done
  } >"$tmp"

  chmod 600 "$tmp"
  mv -f "$tmp" "$ACTIONS_FILE"

  # Niri reloads included configuration files automatically.
  # Give the compositor a short moment to process the reload.
  sleep "$RELOAD_DELAY"
}

enable_action() {
  local name
  local -a enabled

  name="$(normalize_name "$1")"

  action_exists "$name" ||
    die "action does not exist: $(action_file "$name")"

  if action_enabled "$name"; then
    return
  fi

  mapfile -t enabled < <(
    {
      get_enabled_actions
      printf '%s\n' "$name"
    } |
      sort -u
  )

  write_actions "${enabled[@]}"
}

disable_action() {
  local name
  local enabled_name
  local -a enabled=()

  name="$(normalize_name "$1")"

  while IFS= read -r enabled_name; do
    [[ -n "$enabled_name" ]] || continue

    if [[ "$enabled_name" != "$name" ]]; then
      enabled+=("$enabled_name")
    fi
  done < <(get_enabled_actions)

  write_actions "${enabled[@]}"
}

toggle_action() {
  local name

  name="$(normalize_name "$1")"

  action_exists "$name" ||
    die "action does not exist: $(action_file "$name")"

  if action_enabled "$name"; then
    disable_action "$name"
  else
    enable_action "$name"
  fi
}

status_action() {
  local name

  name="$(normalize_name "$1")"

  if action_enabled "$name"; then
    printf 'on\n'
  else
    printf 'off\n'
  fi
}

list_actions() {
  local file
  local name
  local state

  shopt -s nullglob

  for file in "$ACTIONS_DIR"/*.kdl; do
    name="$(basename "$file" .kdl)"

    if action_enabled "$name"; then
      state="on"
    else
      state="off"
    fi

    printf '%-30s %s\n' "$name" "$state"
  done
}

show_active() {
  get_enabled_actions
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") on NAME
  $(basename "$0") off NAME
  $(basename "$0") toggle NAME
  $(basename "$0") status NAME
  $(basename "$0") list
  $(basename "$0") active
EOF
}

main() {
  local command="${1:-}"
  local name="${2:-}"

  # Serialize all reads and writes which can participate in a
  # read-modify-write sequence.
  exec 9>"$LOCK_FILE"
  flock 9

  case "$command" in
  on)
    [[ -n "$name" ]] || die "missing action name"
    enable_action "$name"
    ;;

  off)
    [[ -n "$name" ]] || die "missing action name"
    disable_action "$name"
    ;;

  toggle)
    [[ -n "$name" ]] || die "missing action name"
    toggle_action "$name"
    ;;

  status)
    [[ -n "$name" ]] || die "missing action name"
    status_action "$name"
    ;;

  list)
    list_actions
    ;;

  active)
    show_active
    ;;

  *)
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
