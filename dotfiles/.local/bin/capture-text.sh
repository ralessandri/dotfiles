#!/usr/bin/env bash

set -euo pipefail

readonly OCR_LANGUAGES="deu+eng"

# Command helpers

_show_help() {
  cat <<'EOF'
Usage: capture-text.sh [--notify]

Select a screen region, extract its text, and copy it to the clipboard.

Options:
  -n, --notify  Show a desktop notification after copying the text.
  -h, --help    Show this help message.
EOF
}

_die() {
  printf 'capture-text: %s\n' "$1" >&2
  exit 1
}

_require_command() {
  command -v "$1" >/dev/null 2>&1 || _die "required command not found: $1"
}

# CLI

main() {
  local notify=false
  local geometry
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

  _require_command grim
  _require_command slurp
  _require_command tesseract
  _require_command wl-copy

  if [[ "$notify" == true ]]; then
    _require_command notify-send
  fi

  # Let the user select the area to recognize. Escaping the selector is a normal
  # cancellation and should not be reported as an error.
  geometry="$(slurp)" || return 0
  [[ -n "$geometry" ]] || return 0

  # Keep the image in memory and pass it directly to Tesseract via stdin.
  text="$(grim -g "$geometry" - | tesseract stdin stdout -l "$OCR_LANGUAGES")" ||
    _die "failed to capture or recognize the selected area"

  # Avoid replacing the clipboard when no text was recognized.
  [[ -n "${text//[[:space:]]/}" ]] || return 0

  printf '%s' "$text" | wl-copy || _die "failed to copy recognized text"

  if [[ "$notify" == true ]]; then
    notify-send "OCR" "Recognized text copied to clipboard"
  fi
}

main "$@"
