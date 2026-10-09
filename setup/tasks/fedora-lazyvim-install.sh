#!/usr/bin/env bash
set -euo pipefail

# Configuration

nodejs_version=24

if [[ ! "${nodejs_version}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'ERROR: nodejs_version must be a positive integer.\n' >&2
  exit 1
fi

nodejs_package="nodejs${nodejs_version}"
npm_package="${nodejs_package}-npm"
node_bin_package="${nodejs_package}-bin"
npm_bin_package="${nodejs_package}-npm-bin"

nvim_config="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"
backup_suffix=".bak-$(date +%Y%m%d-%H%M%S)-$$"

# Helpers

_backup_nvim() {
  local path="${1}"

  [[ -e "${path}" || -L "${path}" ]] || return 0
  mv -T -- "${path}" "${path}${backup_suffix}"
  printf 'Backed up %s to %s\n' "${path}" "${path}${backup_suffix}"
}

_check_node_package_available() {
  local package="${1}"

  if rpm -q "${package}" >/dev/null 2>&1; then
    return 0
  fi

  if dnf -q repoquery --available --qf '%{name}' \
    "${package}" 2>/dev/null | grep -Fxq "${package}"; then
    return 0
  fi

  printf 'ERROR: Fedora package "%s" is neither installed nor available in enabled repositories.\n' \
    "${package}" >&2
  return 1
}

_select_default_node_package() {
  local target="${1}"
  local package_pattern="${2}"
  local old

  if rpm -q "${target}" >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r old; do
    [[ -n "${old}" ]] || continue
    sudo dnf swap --allowerasing -y "${old}" "${target}"
    return 0
  done < <(
    rpm -qa --qf '%{NAME}\n' |
      grep -E "${package_pattern}" |
      sort -V || true
  )

  sudo dnf install -y --allowerasing "${target}"
}

# Package installation

printf 'Installing LazyVim prerequisites...\n'
printf 'Selected Node.js major version: %s\n' "${nodejs_version}"

# Verify that all required Node.js packages are available
# before changing the installed configuration.

for package in \
  "${nodejs_package}" \
  "${npm_package}" \
  "${node_bin_package}" \
  "${npm_bin_package}"; do
  _check_node_package_available "${package}"
done

sudo dnf install -y \
  neovim \
  git \
  curl \
  gcc \
  tree-sitter-cli \
  fzf \
  ripgrep \
  fd-find \
  "${nodejs_package}" \
  "${npm_package}"

# Configure the selected Node.js and npm versions as defaults.

printf '\nConfiguring Node.js %s and npm...\n' "${nodejs_version}"

_select_default_node_package \
  "${node_bin_package}" \
  '^nodejs[0-9]+-bin$'

_select_default_node_package \
  "${npm_bin_package}" \
  '^nodejs[0-9]+-npm-bin$'

# Verify active versions.

hash -r

node_version="$(node --version)"
npm_version="$(npm --version)"
npm_major="${npm_version%%.*}"

printf 'Node.js: %s\n' "${node_version}"
printf 'npm:     %s\n' "${npm_version}"

if [[ "${node_version}" != "v${nodejs_version}".* ]]; then
  printf 'ERROR: Expected Node.js %s, got %s\n' \
    "${nodejs_version}" "${node_version}" >&2
  exit 1
fi

if [[ ! "${npm_major}" =~ ^[0-9]+$ ]] ||
  ((npm_major < 11)); then
  printf 'ERROR: Expected npm 11 or newer, got %s\n' \
    "${npm_version}" >&2
  exit 1
fi

# Optionally remove installed Node.js packages
# whose major version is older than the selected version.

old_node_packages=()

while IFS= read -r package; do
  if [[ "${package}" =~ ^nodejs([0-9]+)(-|$) ]]; then
    installed_nodejs_version="${BASH_REMATCH[1]}"

    if ((installed_nodejs_version < nodejs_version)); then
      old_node_packages+=("${package}")
    fi
  fi
done < <(
  rpm -qa --qf '%{NAME}\n' |
    sort -u
)

if ((${#old_node_packages[@]} > 0)); then
  printf '\nFound Node.js packages older than version %s:\n' \
    "${nodejs_version}"
  printf '  - %s\n' "${old_node_packages[@]}"

  if gum confirm "Remove these older Node.js packages?"; then
    sudo dnf remove "${old_node_packages[@]}"
  else
    printf 'Keeping older Node.js packages.\n'
  fi
fi

if ! command -v lazygit >/dev/null 2>&1 &&
  gum confirm 'Install lazygit for Git integration?'; then
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
