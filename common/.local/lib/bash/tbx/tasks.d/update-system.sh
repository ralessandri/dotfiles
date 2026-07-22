#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/common/.local/lib/bash/core/init.sh"

update_apt() {
  print_section "APT Update"

  run_and_report "sudo apt update -qq" \
    "APT update completed." \
    "Error during APT update."

  run_and_report "sudo apt upgrade -y" \
    "APT upgrade completed." \
    "Error during APT upgrade."

  run_and_report "sudo apt autoremove -y" \
    "Unused APT packages removed." \
    "Error during APT autoremove."
}

update_dnf() {
  print_section "DNF Update"

  run_and_report "sudo dnf upgrade -y" \
    "DNF upgrade completed." \
    "Error during DNF upgrade."

  run_and_report "sudo dnf autoremove -y" \
    "Unused DNF packages removed." \
    "Error during DNF autoremove."
}

update_flatpak() {
  print_section "Flatpak Update"

  run_and_report "flatpak update -y" \
    "Flatpak update completed." \
    "Error during Flatpak update."

  run_and_report "flatpak uninstall --unused" \
    "Unused Flatpak packages removed." \
    "Error during Flatpak cleanup."
}

update_brew() {
  print_section "Homebrew Update"

  run_and_report "brew update" \
    "Homebrew update completed." \
    "Error during Homebrew update."

  if brew outdated | grep -q .; then
    run_and_report "brew upgrade" \
      "Homebrew packages upgraded." \
      "Error during Homebrew upgrade."

    run_and_report "brew cleanup --prune=all" \
      "Homebrew cleanup completed." \
      "Error during Homebrew cleanup."

    run_and_report "brew autoremove" \
      "Unused Homebrew packages removed." \
      "Error during Homebrew autoremove."
  else
    success_message "All Homebrew packages are up to date. 🎉"
  fi
}

main() {
  available apt && update_apt
  available dnf && update_dnf
  available flatpak && update_flatpak
  available brew && update_brew
}

main "$@"
