#!/usr/bin/env bash
set -euo pipefail

DUX_REPO='/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:duxlabs:dux.repo'
DMS_REPO='/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:duxlabs:dms.repo'

if [[ ! -f "${DUX_REPO}" ]]; then
  printf 'Enabling Dux Core COPR repository...\n'
  sudo dnf copr enable -y duxlabs/dux
fi

if [[ ! -f "${DMS_REPO}" ]]; then
  printf 'Enabling Dux Shell COPR repository...\n'
  sudo dnf copr enable -y duxlabs/dms
fi

printf 'Installing Niri and Dux Shell...\n'

sudo dnf install -y \
  niri \
  dms \
  matugen

printf 'Integrating Dux Shell with Niri...\n'

dms systemd enable --compositor niri

if gum confirm 'Install and enable dms-greeter (replaces the current display manager)?'; then
  printf 'Installing Dux Greeter...\n'
  sudo dnf install -y greetd dms-greeter

  printf 'Enabling Dux Greeter and syncing its theme...\n'
  dms-greeter enable --yes
  dms-greeter sync --yes
fi

printf '\nNiri and Dux Shell setup complete.\n'
