#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ -f "$HOME/.env" ]] && source "$HOME/.env" || {
  echo "Error: $HOME/.env not found" >&2
  exit 1
}
source "$TBX_UTILS"

print_section "Configuring  DNF..."
sudo sed -i '/^max_parallel_downloads=/c\max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >>/etc/dnf/dnf.conf
grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
sudo dnf install dnf-plugins-core

success_message "DNF Configured Successfully"
