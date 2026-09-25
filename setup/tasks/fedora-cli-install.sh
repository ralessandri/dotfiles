#!/usr/bin/env bash
set -euo pipefail

# COPR repositories
enabled_repos="$(dnf repo list --enabled)"

if ! awk -v repo_id='copr:copr.fedorainfracloud.org:dejan:lazygit' '$1 == repo_id { found = 1 } END { exit !found }' <<<"${enabled_repos}"; then
  printf 'Enabling lazygit COPR repository...\n'
  sudo dnf copr enable -y dejan/lazygit
fi

if ! awk -v repo_id='copr:copr.fedorainfracloud.org:mineiro:satty' '$1 == repo_id { found = 1 } END { exit !found }' <<<"${enabled_repos}"; then
  printf 'Enabling satty COPR repository...\n'
  sudo dnf copr enable -y mineiro/satty
fi

# RPM packages
packages=(
  bat
  curl
  eza
  fd-find
  flatpak
  fontconfig
  fzf
  git
  gum
  jq
  just
  lazygit
  libnotify
  neovim
  nss-mdns
  ripgrep
  rofi
  satty
  shfmt
  stow
  tar
  tesseract
  tesseract-langpack-deu
  tesseract-langpack-eng
  tree
  tuned
  tuned-ppd
  udisks2
  xdg-user-dirs
  xz
  zoxide
)

printf 'Installing CLI tools...\n'
sudo dnf --refresh install -y "${packages[@]}"

printf 'Updating CLI tools...\n'
sudo dnf upgrade -y "${packages[@]}"

# Herdr
printf 'Installing or updating Herdr...\n'
herdr_bin="${HOME}/.local/bin/herdr"
if [[ -x "${herdr_bin}" ]]; then
  "${herdr_bin}" update
else
  curl -fsSL https://herdr.dev/install.sh | sh
fi

# Flatpak
printf 'Configuring Flathub...\n'
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak remote-modify --enable flathub

printf 'Installing or updating Flatpak applications...\n'
sudo flatpak install -y --or-update flathub org.chromium.Chromium
sudo flatpak install -y --or-update flathub org.mozilla.firefox

# Nerd Font
printf 'Installing JetBrainsMono Nerd Font...\n'
font_dir="${HOME}/.local/share/fonts/JetBrainsMono"
mkdir -p "${font_dir}"
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz |
  tar -xJf - -C "${font_dir}"
fc-cache -f "${font_dir}"

printf '\nCLI tools setup complete.\n'
