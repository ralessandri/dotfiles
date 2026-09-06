#!/usr/bin/env bash

set -euo pipefail

readonly OCR_LANGUAGES="deu+eng"

show_help() {
  cat <<'EOF'
Usage: capture-text.sh [--notify]

Select a screen region, extract its text, and copy it to the clipboard.

Options:
  -n, --notify  Show a desktop notification after copying the text.
  -h, --help    Show this help message.
EOF
}

die() {
  printf 'capture-text: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

notify=false

while (($# > 0)); do
  case "$1" in
    -n|--notify)
      notify=true
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      show_help >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

require_command grim
require_command slurp
require_command tesseract
require_command wl-copy

if [[ "$notify" == true ]]; then
  require_command notify-send
fi

# Let the user select the area to recognize. Escaping the selector is a normal
# cancellation and should not be reported as an error.
geometry="$(slurp)" || exit 0
[[ -n "$geometry" ]] || exit 0

# Keep the image in memory and pass it directly to Tesseract via stdin.
text="$(grim -g "$geometry" - | tesseract stdin stdout -l "$OCR_LANGUAGES")" ||
  die "failed to capture or recognize the selected area"

# Avoid replacing the clipboard when no text was recognized.
[[ -n "${text//[[:space:]]/}" ]] || exit 0

printf '%s' "$text" | wl-copy || die "failed to copy recognized text"

if [[ "$notify" == true ]]; then
  notify-send "OCR" "Recognized text copied to clipboard"
fi
