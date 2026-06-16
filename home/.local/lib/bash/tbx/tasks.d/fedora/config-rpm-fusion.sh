#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/utils.sh"

if [ ! -e /etc/yum.repos.d/rpmfusion-free.repo ] || [ ! -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
  print_section "Installing RPM Fusion..."
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

  sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
  sudo dnf install -y rpmfusion-\*-appstream-data
else
  info_message "RPM Fusion already installed"
fi

if [ ! -e /etc/yum.repos.d/rpmfusion-free-tainted.repo ] || [ ! -e /etc/yum.repos.d/rpmfusion-nonfree-tainted.repo ]; then
  printf "%b\n" "${PASTEL_YELLOW}Do you want to install tainted repositories? [y/N]: ${NC}"
  read -r install_tainted
  case "$install_tainted" in
  [Yy]*)
    print_section "Installing RPM Fusion tainted repositories..."
    sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

    sudo dnf config-manager setopt rpmfusion-free-tainted.enabled=1
    sudo dnf config-manager setopt rpmfusion-nonfree-tainted.enabled=1

    success_message "Tainted repositories installed and enabled"
    ;;
  *)
    info_message "Skipping tainted repositories..."
    ;;
  esac
else
  info_message "Tainted repositories already installed"
fi
