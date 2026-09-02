#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/common/.local/lib/bash/core/init.sh"

if [ -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
  # Check if NVIDIA driver is already installed
  if ! rpm -q akmod-nvidia &>/dev/null; then
    print_section "Installing NVIDIA proprietary drivers and libraries..."
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-cuda-libs

    # Ensure the kernel modules are built
    print_section "Building NVIDIA kernel modules..."
    sudo akmods --force

    # Enable NVIDIA driver services
    print_section "Enabling NVIDIA services..."
    sudo systemctl enable nvidia-hibernate nvidia-suspend nvidia-resume nvidia-powerd

    success_message "NVIDIA proprietary drivers and libraries installed successfully"
  else
    info_message "NVIDIA proprietary drivers already installed"
  fi

  # Optional: Install additional NVIDIA utilities
  if ! rpm -q akmod-nvidia &>/dev/null; then
    printf "%b\n" "${PASTEL_YELLOW}Do you want to install additional NVIDIA utilities (e.g., nvidia-settings)? [y/N]: ${NC}"
    read -r install_utils
    case "$install_utils" in
    [Yy]*)
      print_section "Installing NVIDIA utilities..."
      sudo dnf install -y nvidia-settings
      success_message "NVIDIA utilities installed"
      ;;
    *)
      print_section "Skipping NVIDIA utilities..."
      ;;
    esac
  else
    info_message "NVIDIA utilities already installed"
  fi
else
  error_message "RPM Fusion Nonfree repositories not detected. Please set up RPM Fusion first!"
fi
