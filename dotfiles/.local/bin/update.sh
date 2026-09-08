#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"

have_command() {
  command -v "$1" >/dev/null 2>&1
}

show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Update installed packages and clean up unused packages for every supported
package manager found on the system.

Options:
  -h, --help  Show this help message and exit.

Supported package managers:
  apt       Run apt update, apt upgrade, and apt autoremove.
  dnf       Run dnf upgrade and dnf autoremove.
  flatpak   Run flatpak update and remove unused Flatpak packages.
  brew      Run brew update, brew upgrade, brew cleanup, and brew autoremove
            when outdated packages are found.

Notes:
  - Only package managers available on the current system are used.
  - Commands that require elevated privileges may prompt for sudo access.
EOF
}

print_header() {
  printf '\n:: %s\n\n' "$1"
}

run_step() {
  local success_message="$1"
  local error_message="$2"
  shift 2

  if "$@"; then
    printf '%s\n' "$success_message"
  else
    printf '%s\n' "$error_message" >&2
    return 1
  fi
}

update_apt() {
  print_header "APT Update"

  run_step "APT update completed." "Error during APT update." sudo apt update -qq
  run_step "APT upgrade completed." "Error during APT upgrade." sudo apt upgrade -y
  run_step "Unused APT packages removed." "Error during APT autoremove." sudo apt autoremove -y
}

update_dnf() {
  print_header "DNF Update"

  run_step "DNF upgrade completed." "Error during DNF upgrade." sudo dnf upgrade --refresh -y
  run_step "Unused DNF packages removed." "Error during DNF autoremove." sudo dnf autoremove -y
}

update_flatpak() {
  print_header "Flatpak Update"

  run_step "Flatpak update completed." "Error during Flatpak update." sudo flatpak update -y
  run_step "Unused Flatpak packages removed." "Error during Flatpak cleanup." sudo flatpak uninstall --unused
}

update_brew() {
  print_header "Homebrew Update"

  run_step "Homebrew update completed." "Error during Homebrew update." brew update

  if brew outdated | grep -q .; then
    run_step "Homebrew packages upgraded." "Error during Homebrew upgrade." brew upgrade
    run_step "Homebrew cleanup completed." "Error during Homebrew cleanup." brew cleanup --prune=all
    run_step "Unused Homebrew packages removed." "Error during Homebrew autoremove." brew autoremove
  else
    printf 'All Homebrew packages are up to date. 🎉\n'
  fi
}

main() {
  while (($# > 0)); do
    case "$1" in
    -h | --help)
      show_help
      return 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      printf 'Try %s --help for usage information.\n' "$SCRIPT_NAME" >&2
      return 1
      ;;
    esac
  done

  have_command apt && update_apt
  have_command dnf && update_dnf
  have_command flatpak && update_flatpak
  have_command brew && update_brew
}

main "$@"
