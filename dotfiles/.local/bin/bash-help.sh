#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
readonly BASHRC_DIR="${DOTFILES_DIR}/.bashrc.d"

_show_help() {
  cat <<'EOF'
Usage: bash-help.sh [--help]

Browse documented Bash aliases and functions with fzf.

The description is read from the contiguous comment block directly above each
definition in ~/.bashrc.d. The preview shows that comment block and source.

Options:
  -h, --help  Show this help message.
EOF
}

_die() {
  printf 'bash-help: %s\n' "$1" >&2
  exit 1
}

_require_command() {
  command -v "$1" >/dev/null 2>&1 || _die "required command not found: $1"
}

_description_from_comments() {
  local comment

  for comment in "$@"; do
    [[ -z "$comment" || "$comment" =~ ^#{3,}$ ]] && continue
    printf '%s' "$comment"
    return
  done

  printf '%s' 'No description available.'
}

_collect_entries_from_file() {
  local file="$1"
  local line
  local line_number=0
  local comment
  local comment_start=0
  local -a comments=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))

    if [[ "$line" =~ ^[[:space:]]*#(.*)$ ]]; then
      comment="${BASH_REMATCH[1]}"
      comment="${comment# }"

      if ((${#comments[@]} == 0)); then
        comment_start=$line_number
      fi

      comments+=("$comment")
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*alias[[:space:]]+([^=[:space:]]+)= ]]; then
      printf 'alias\t%s\t%s\t%s\t%s\t%s\n' \
        "${BASH_REMATCH[1]}" \
        "$(_description_from_comments "${comments[@]}")" \
        "$file" \
        "$line_number" \
        "$comment_start"
    elif [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+)?([[:alnum:]_-]+)[[:space:]]*\(\)[[:space:]]*\{ ]] && [[ "${BASH_REMATCH[2]}" != _* ]]; then
      printf 'function\t%s\t%s\t%s\t%s\t%s\n' \
        "${BASH_REMATCH[2]}" \
        "$(_description_from_comments "${comments[@]}")" \
        "$file" \
        "$line_number" \
        "$comment_start"
    fi

    comments=()
    comment_start=0
  done <"$file"
}

_collect_entries() {
  local file

  for file in "${BASHRC_DIR}"/*.sh; do
    [[ -f "$file" ]] || continue
    _collect_entries_from_file "$file"
  done
}

_preview_entry() {
  local file="$1"
  local comment_start="$2"
  local definition_line="$3"
  local definition
  local source_start="$comment_start"
  local source_end=$((definition_line + 24))

  if ((source_start == 0)); then
    source_start=$definition_line
  fi

  definition="$(sed -n "${definition_line}p" "$file")"
  if [[ "$definition" =~ ^[[:space:]]*alias[[:space:]] ]]; then
    source_end=$definition_line
  fi

  sed -n "${source_start},${source_end}p" "$file"
}

_show_browser() {
  local selected
  local kind
  local name
  local description
  local file
  local definition_line
  local comment_start

  selected="$(
    _collect_entries |
      sort -t $'\t' -k 2,2 |
      fzf \
        --delimiter=$'\t' \
        --preview="${SCRIPT_PATH} --preview {4} {6} {5}" \
        --preview-label='alt-p: toggle source, alt-j/k: scroll, F11: maximize' \
        --preview-label-pos='bottom' \
        --preview-window='down:50%:wrap' \
        --bind='alt-p:toggle-preview' \
        --bind='alt-d:preview-half-page-down,alt-u:preview-half-page-up' \
        --bind='alt-k:preview-up,alt-j:preview-down' \
        --header='Enter: show source | Esc: cancel' \
        --layout=reverse \
        --prompt='Shell help> ' \
        --with-nth=1,2,3
  )" || return 0

  IFS=$'\t' read -r kind name description file definition_line comment_start <<<"$selected"
  printf '%s: %s\n\n' "$name" "$description"
  _preview_entry "$file" "$comment_start" "$definition_line"
}

case "${1:-}" in
'')
  _require_command fzf
  _show_browser
  ;;
-h | --help)
  _show_help
  ;;
--preview)
  (($# == 4)) || _die '--preview requires FILE COMMENT_START DEFINITION_LINE'
  _preview_entry "$2" "$3" "$4"
  ;;
*)
  _die "unknown option: $1"
  ;;
esac
