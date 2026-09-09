#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"

# Command helpers

_has_command() {
  command -v "$1" >/dev/null 2>&1
}

_show_help() {
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

_print_section_header() {
  printf '\n:: %s\n\n' "$1"
}

_run_reported_step() {
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

# Package-manager workflows

_update_apt() {
  _print_section_header "APT Update"

  _run_reported_step "APT update completed." "Error during APT update." sudo apt update -qq
  _run_reported_step "APT upgrade completed." "Error during APT upgrade." sudo apt upgrade -y
  _run_reported_step "Unused APT packages removed." "Error during APT autoremove." sudo apt autoremove -y
}

_update_dnf() {
  _print_section_header "DNF Update"

  _run_reported_step "DNF upgrade completed." "Error during DNF upgrade." sudo dnf upgrade --refresh -y
  _run_reported_step "Unused DNF packages removed." "Error during DNF autoremove." sudo dnf autoremove -y
}

_update_flatpak() {
  _print_section_header "Flatpak Update"

  _run_reported_step "Flatpak update completed." "Error during Flatpak update." sudo flatpak update -y
  _run_reported_step "Unused Flatpak packages removed." "Error during Flatpak cleanup." sudo flatpak uninstall --unused
}

_update_brew() {
  local outdated_packages

  _print_section_header "Homebrew Update"

  _run_reported_step "Homebrew update completed." "Error during Homebrew update." brew update

  if ! outdated_packages="$(brew outdated)"; then
    printf 'Error checking outdated Homebrew packages.\n' >&2
    return 1
  fi

  if [[ -n "$outdated_packages" ]]; then
    _run_reported_step "Homebrew packages upgraded." "Error during Homebrew upgrade." brew upgrade
    _run_reported_step "Homebrew cleanup completed." "Error during Homebrew cleanup." brew cleanup --prune=all
    _run_reported_step "Unused Homebrew packages removed." "Error during Homebrew autoremove." brew autoremove
  else
    printf 'All Homebrew packages are up to date. 🎉\n'
  fi
}

# CLI

main() {
  local package_manager_found=false

  while (($# > 0)); do
    case "$1" in
    -h | --help)
      _show_help
      return 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      printf 'Try %s --help for usage information.\n' "$SCRIPT_NAME" >&2
      return 1
      ;;
    esac
  done

  if _has_command apt; then
    _update_apt
    package_manager_found=true
  fi

  if _has_command dnf; then
    _update_dnf
    package_manager_found=true
  fi

  if _has_command flatpak; then
    _update_flatpak
    package_manager_found=true
  fi

  if _has_command brew; then
    _update_brew
    package_manager_found=true
  fi

  if [[ "$package_manager_found" == false ]]; then
    printf 'No supported package manager found.\n' >&2
    return 1
  fi
}

main "$@"
