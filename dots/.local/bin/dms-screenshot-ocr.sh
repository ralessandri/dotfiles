#!/usr/bin/env bash

set -euo pipefail

readonly OCR_LANGUAGES="deu+eng"

# Command helpers

_show_help() {
  cat <<'EOF'
Usage: dms-screenshot-ocr.sh [--notify]

Select a screen region, extract its text, and copy it to the clipboard.

Options:
  -n, --notify  Show a desktop notification after copying the text.
  -h, --help    Show this help message.
EOF
}

_die() {
  printf 'dms-screenshot-ocr: %s\n' "$1" >&2
  exit "${2:-1}"
}

_require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    _die "required command not found: $1"
}

# Screenshot and OCR

# The subshell keeps the temporary path available to its EXIT trap.
_capture_text() (
  screenshot_file=""

  [[ -n "${XDG_RUNTIME_DIR:-}" ]] ||
    _die "XDG_RUNTIME_DIR is not set"

  # The private runtime file keeps binary PNG data out of Bash variables and
  # lets us distinguish an empty, cancelled capture from a Tesseract failure.
  screenshot_file="$(mktemp "${XDG_RUNTIME_DIR}/dms-screenshot-ocr.XXXXXXXX")" ||
    _die "failed to create temporary screenshot file"
  trap 'rm -f -- "${screenshot_file}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  dms screenshot --stdout --no-file --no-clipboard --no-notify >"${screenshot_file}" ||
    _die "failed to capture the selected area" "$?"
  [[ -s "${screenshot_file}" ]] || exit 0

  tesseract stdin stdout -l "${OCR_LANGUAGES}" <"${screenshot_file}" ||
    _die "failed to recognize the selected area" "$?"
)

# CLI

main() {
  local notify=false
  local text

  while (($# > 0)); do
    case "$1" in
    -n | --notify)
      notify=true
      ;;
    -h | --help)
      _show_help
      return 0
      ;;
    *)
      _show_help >&2
      _die "unknown option: $1"
      ;;
    esac
    shift
  done

  _require_command dms
  _require_command tesseract
  _require_command wl-copy

  if [[ "$notify" == true ]]; then
    _require_command notify-send
  fi

  text="$(_capture_text)" || return "$?"

  # Avoid replacing the clipboard when no text was recognized.
  [[ -n "${text//[[:space:]]/}" ]] || return 0

  printf '%s' "$text" | wl-copy ||
    _die "failed to copy recognized text"

  if [[ "$notify" == true ]]; then
    notify-send "OCR" "Recognized text copied to clipboard"
  fi
}

main "$@"
