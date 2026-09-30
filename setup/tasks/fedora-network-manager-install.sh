#!/usr/bin/env bash
set -euo pipefail

printf 'Installing NetworkManager and connection editor...\n'

sudo dnf install -y \
  NetworkManager \
  NetworkManager-wifi \
  nm-connection-editor \
  nm-connection-editor-desktop

printf '\nNetworkManager setup complete.\n'
