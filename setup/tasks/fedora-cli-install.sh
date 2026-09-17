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
  flatpak \
  fontconfig \
  fzf \
  git \
  gum \
  just \
  lazygit \
  libnotify \
  neovim \
  nss-mdns \
  jq \
  rofi \
  ripgrep \
  shfmt \
  stow \
  tar \
  tree \
  tuned \
  tuned-ppd \
  udisks2 \
  xdg-user-dirs \
  zoxide

printf 'Installing Herdr...\n'
curl -fsSL https://herdr.dev/install.sh | sh

printf 'Configuring Flathub...\n'
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

printf 'Installing Flatpak applications...\n'
sudo flatpak install -y flathub org.chromium.Chromium
sudo flatpak install -y flathub org.mozilla.firefox

printf 'Installing JetBrainsMono Nerd Font...\n'
font_dir="${HOME}/.local/share/fonts/JetBrainsMono"
mkdir -p "${font_dir}"
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz |
  tar -xJf - -C "${font_dir}"
fc-cache -f "${font_dir}"

printf '\nCLI tools setup complete.\n'
