#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/common/.local/lib/bash/core/init.sh"
source "$HOME/.dotfiles/common/.local/lib/bash/tbx/gui/gum.sh"

print_section ":: Welcome to MyLinux Toolbox!"

if ! available gum; then
  print_section "Installing gum..."
  sudo dnf install -y gum
fi

show_menu "$TBX_TASKS_DIR"
