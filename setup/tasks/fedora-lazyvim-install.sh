#!/usr/bin/env bash
set -euo pipefail

# Configuration

nvim_config="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"
backup_suffix=".bak-$(date +%Y%m%d-%H%M%S)-$$"

# Helpers

_backup_nvim() {
  local path="${1}"

  [[ -e "${path}" || -L "${path}" ]] || return 0
  mv -T -- "${path}" "${path}${backup_suffix}"
  printf 'Backed up %s to %s\n' "${path}" "${path}${backup_suffix}"
}

# Package installation

printf 'Installing LazyVim prerequisites...\n'

sudo dnf install -y \
  neovim \
  git \
  curl \
  gcc \
  tree-sitter-cli \
  fzf \
  ripgrep \
  fd-find

if ! command -v lazygit >/dev/null 2>&1 && gum confirm 'Install lazygit for Git integration?'; then
  sudo dnf copr enable -y dejan/lazygit
  sudo dnf install -y lazygit
fi

# Neovim configuration

if [[ ! -e "${nvim_config}" && ! -L "${nvim_config}" ]] ||
  gum confirm "Back up ${nvim_config} and replace it with the LazyVim starter?"; then
  _backup_nvim "${nvim_config}"

  if gum confirm 'Back up existing Neovim data, state and cache (recommended)?'; then
    _backup_nvim "${XDG_DATA_HOME:-${HOME}/.local/share}/nvim"
    _backup_nvim "${XDG_STATE_HOME:-${HOME}/.local/state}/nvim"
    _backup_nvim "${XDG_CACHE_HOME:-${HOME}/.cache}/nvim"
  fi

  mkdir -p -- "$(dirname -- "${nvim_config}")"
  git clone https://github.com/LazyVim/starter "${nvim_config}"
  rm -rf -- "${nvim_config}/.git"
fi

# Health check

printf '\nLazyVim setup complete.\n'
printf 'Start Neovim in foot and run :LazyHealth to check the installation.\n'

if gum confirm 'Start Neovim and run :LazyHealth now?'; then
  nvim +LazyHealth
fi
