#!/usr/bin/env bash
set -euo pipefail

DANKLINUX_REPO='/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:danklinux.repo'
DMS_REPO='/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:dms.repo'

if [[ ! -f "$DANKLINUX_REPO" ]]; then
  printf 'Enabling DankLinux COPR repository...\n'
  sudo dnf copr enable -y avengemedia/danklinux
fi

if [[ ! -f "$DMS_REPO" ]]; then
  printf 'Enabling DMS COPR repository...\n'
  sudo dnf copr enable -y avengemedia/dms
fi

printf 'Installing Niri and Dank Material Shell...\n'

sudo dnf install -y \
  niri \
  dms \
  matugen

printf 'Integrating DMS with Niri...\n'

systemctl --user add-wants niri.service dms

printf '\nNiri and Dank Material Shell setup complete.\n'
