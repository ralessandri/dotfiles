#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/init.sh"

if [ -e /etc/yum.repos.d/rpmfusion-free.repo ] && [ -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
  print_section "Installing Multimedia Codecs"

  # Swap ffmpeg-free for proprietary ffmpeg (allows proprietary codecs)
  sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y

  # Install GStreamer plugins and other home multimedia codecs
  sudo dnf install -y \
    gstreamer1-plugins-{base,good,bad-free,bad-free-extras,ugly} \
    gstreamer1-plugin-openh264 \
    gstreamer1-libav \
    lame\* \
    x264\* \
    x265\* \
    ffmpeg

  success_message "Multimedia Codecs Installed Successfully"
else
  error_message "RPM Fusion repositories not found. Please set up RPM Fusion first!"
fi
