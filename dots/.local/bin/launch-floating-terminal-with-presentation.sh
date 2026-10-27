#!/usr/bin/env bash
set -euo pipefail

show_help() {
  printf '%s\n' \
    'Usage: launch-floating-terminal-with-presentation.sh [--title TITLE] COMMAND [ARG...]' \
    '       launch-floating-terminal-with-presentation.sh [--title TITLE] -- COMMAND [ARG...]' \
    '' \
    'Show an optional title, run a command in the current terminal, and wait for a key after it exits.' \
    'The title is displayed as a section header.' \
    'A command exit status of 130 skips the final prompt.'
}

wait_for_key() {
  local message="$1"

  [[ -r /dev/tty && -w /dev/tty ]] || return 0

  while IFS= read -r -s -n 1 -t 0.1 </dev/tty; do :; done
  printf '\n%s' "${message}" >/dev/tty
  IFS= read -r -s -n 1 </dev/tty || true
  printf '\n' >/dev/tty
}

if (($# > 0)) && [[ "$1" == --help || "$1" == -h ]]; then
  show_help
  exit 0
fi

title=""
if (($# > 0)) && [[ "$1" == --title ]]; then
  if (($# < 2)) || [[ -z "$2" ]]; then
    printf '%s\n' 'Error: --title requires a non-empty title.' >&2
    exit 2
  fi
  title="$2"
  shift 2
fi

if (($# > 0)) && [[ "$1" == -- ]]; then
  shift
fi

if (($# == 0)); then
  show_help >&2
  exit 2
fi

if [[ -n "$title" ]]; then
  printf '\n:: %s\n\n' "$title"
fi

status=0
"$@" || status=$?

if ((status != 130)); then
  if ((status == 0)); then
    wait_for_key '● Done! Press any key to close...'
  else
    wait_for_key "● Failed (exit status ${status}). Press any key to close..."
  fi
fi

exit "${status}"
