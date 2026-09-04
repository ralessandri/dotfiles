#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
  printf 'RPM Fusion Nonfree repository is required.\n' >&2
  exit 1
fi

printf 'Installing NVIDIA 580xx drivers...\n'

sudo dnf install -y \
  akmod-nvidia-580xx \
  xorg-x11-drv-nvidia-580xx \
  xorg-x11-drv-nvidia-580xx-cuda \
  xorg-x11-drv-nvidia-580xx-libs \
  xorg-x11-drv-nvidia-580xx-cuda-libs \
  nvidia-settings-580xx

printf 'Enabling NVIDIA services...\n'

sudo systemctl enable \
  nvidia-hibernate.service \
  nvidia-suspend.service \
  nvidia-resume.service \
  nvidia-powerd.service

printf '\nNVIDIA 580xx setup complete.\n'
