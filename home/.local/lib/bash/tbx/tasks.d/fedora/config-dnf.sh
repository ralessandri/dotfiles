#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/utils.sh"

print_section "Configuring  DNF..."
sudo sed -i '/^max_parallel_downloads=/c\max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >>/etc/dnf/dnf.conf
grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
sudo dnf install dnf-plugins-core

success_message "DNF Configured Successfully"
