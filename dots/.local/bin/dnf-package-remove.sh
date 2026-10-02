#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_PATH="$(readlink -f "$0")"

show_help() {
  cat <<'EOF'
Usage: dnf-package-remove.sh [--terminal TERMINAL]

Search explicitly user-installed Fedora packages with fzf and remove the selected packages.

Options:
  --terminal TERMINAL  Use alacritty, wezterm, or foot (default: alacritty).
  -h, --help           Show this help message.
EOF
}

die() {
  printf 'dnf-package-remove: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_in_terminal() {
  local terminal="$1"

  command -v "$terminal" >/dev/null 2>&1 ||
    die "terminal not found: $terminal"

  case "$terminal" in
  wezterm)
    exec wezterm start --class dnf-package-remove --always-new-process -- "$SCRIPT_PATH" --in-terminal
    ;;
  foot)
    exec foot --app-id=dnf-package-remove "$SCRIPT_PATH" --in-terminal
    ;;
  alacritty)
    exec alacritty --class dnf-package-remove -e "$SCRIPT_PATH" --in-terminal
    ;;
  *)
    die "unsupported terminal: $terminal (choose alacritty, wezterm, or foot)"
    ;;
  esac
}

terminal='alacritty'
in_terminal=false

while (($# > 0)); do
  case "$1" in
  --terminal)
    (($# >= 2)) || die '--terminal requires a value'
    terminal="$2"
    shift 2
    ;;
  --terminal=*)
    terminal="${1#*=}"
    shift
    ;;
  --in-terminal)
    in_terminal=true
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
done

if [[ "$in_terminal" == false ]]; then
  run_in_terminal "$terminal"
fi

require_command dnf
require_command fzf
require_command sudo

installonly_file="$(mktemp)"
trap 'rm -f "$installonly_file"' EXIT

# Keep install-only packages, such as kernels, out of the removal candidates.
dnf repoquery --installonly --queryformat='%{name}\n' 2>/dev/null >"$installonly_file"

printf 'Loading user-installed Fedora packages...\n' >&2

selected_line="$(
  dnf repoquery --leaves --queryformat=$'%{name}\t%{reason}\t%{summary}\n' 2>/dev/null |
    awk -F $'\t' -v excluded_file="$installonly_file" '
      BEGIN {
        while ((getline package < excluded_file) > 0) {
          excluded[package] = 1
        }
        close(excluded_file)
      }
      $2 == "User" && !($1 in excluded) { print $1 "\t" $3 }
    ' |
    awk -F $'\t' '!seen[$1]++' |
    fzf \
      --multi \
      --delimiter=$'\t' \
      --preview='dnf info --installed -- {1}' \
      --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select, F11: maximize' \
      --preview-label-pos='bottom' \
      --preview-window='down:50%:wrap' \
      --bind='alt-p:toggle-preview' \
      --bind='alt-d:preview-half-page-down,alt-u:preview-half-page-up' \
      --bind='alt-k:preview-up,alt-j:preview-down' \
      --color='fg:#dfe3e7,bg:-1,fg+:#00344a,bg+:#90cef4,hl:#90cef4,hl+:#00344a,info:#90cef4,prompt:#90cef4,pointer:#90cef4,marker:#90cef4,spinner:#90cef4,header:#dfe3e7,border:#90cef4,separator:#90cef4,preview-border:#90cef4,preview-fg:#dfe3e7,preview-bg:-1' \
      --header='Enter: remove | Esc: cancel' \
      --layout=reverse \
      --prompt='Package> ' \
      --with-nth=1,2
)" || exit 0

mapfile -t packages < <(
  while IFS= read -r line; do
    package="${line%%$'\t'*}"
    [[ -n "$package" ]] && printf '%s\n' "$package"
  done <<<"$selected_line"
)

((${#packages[@]} > 0)) || exit 0

printf '\nSelected package(s): %s\n' "${packages[*]}"
read -r -p 'Remove these packages? [y/N] ' answer
[[ "$answer" =~ ^[Yy]$ ]] || exit 0

printf '\nRemoving package(s): %s\n\n' "${packages[*]}"
sudo dnf remove "${packages[@]}"

printf '\nPackage removal finished. Press Enter to close.\n'
read -r
