#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/rpmfusion-free.repo ]] ||
  [[ ! -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
  printf 'Installing RPM Fusion repositories...\n'

  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
fi

printf 'Configuring RPM Fusion...\n'

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

sudo dnf install -y \
  rpmfusion-free-appstream-data \
  rpmfusion-nonfree-appstream-data

if [[ ! -f /etc/yum.repos.d/rpmfusion-free-tainted.repo ]] ||
  [[ ! -f /etc/yum.repos.d/rpmfusion-nonfree-tainted.repo ]]; then
  printf 'Installing RPM Fusion tainted repositories...\n'

  sudo dnf install -y \
    rpmfusion-free-release-tainted \
    rpmfusion-nonfree-release-tainted
fi

printf '\nRPM Fusion setup complete.\n'
