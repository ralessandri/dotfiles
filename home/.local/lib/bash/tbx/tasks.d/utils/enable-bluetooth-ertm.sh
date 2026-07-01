#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/init.sh"

echo N | sudo tee /sys/module/bluetooth/parameters/disable_ertm >/dev/null
success_message "Bluetooth ERTM enabled"
