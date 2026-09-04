#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:dejan:lazygit.repo ]]; then
  printf 'Enabling lazygit COPR repository...\n'
  sudo dnf copr enable -y dejan/lazygit
fi

printf 'Installing CLI tools...\n'

sudo dnf install -y \
  bat \
  eza \
  fd-find \
  fzf \
  gum \
  just \
  lazygit \
  neovim \
  ripgrep \
  shfmt \
  stow \
  zoxide

printf '\nCLI tools setup complete.\n'
