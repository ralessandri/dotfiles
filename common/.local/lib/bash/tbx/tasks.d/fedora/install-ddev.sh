#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/init.sh"

# Add DDEV releases to your package repository
if [ ! -e /etc/yum.repos.d/ddev.repo ]; then
  print_section "Adding DDEV repository..."
  sudo sh -c 'echo ""'
  echo '[ddev]
name=ddev
baseurl=https://pkg.ddev.com/yum/
gpgcheck=0
enabled=1' | perl -p -e 's/^ +//' | sudo tee /etc/yum.repos.d/ddev.repo >/dev/null
else
  info_message "DDEV repository already exists"
fi

# Install DDEV
if ! available ddev; then
  print_section "Installing DDEV..."
  sudo dnf install -y --refresh ddev
  success_message "DDEV installed successfully"
else
  info_message "DDEV is already installed"
fi

# One-time initialization of mkcert
if ! mkcert -CAROOT &>/dev/null; then
  print_section "Initializing mkcert..."
  mkcert -install
  success_message "mkcert initialized"
else
  info_message "mkcert already initialized"
fi
