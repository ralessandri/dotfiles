#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/rpmfusion-free.repo ]] ||
  [[ ! -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
  printf 'RPM Fusion Free and Nonfree repositories are required.\n' >&2
  exit 1
fi

printf 'Installing multimedia codecs...\n'

sudo dnf swap -y \
  ffmpeg-free \
  ffmpeg \
  --allowerasing

sudo dnf install -y \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-free-extras \
  gstreamer1-plugins-ugly \
  gstreamer1-plugin-openh264 \
  gstreamer1-libav \
  lame \
  x264 \
  x265 \
  ffmpeg

printf '\nMultimedia codec setup complete.\n'
