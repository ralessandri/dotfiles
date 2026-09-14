#!/usr/bin/env bash
set -euo pipefail

# Package installation

printf 'Installing Intel Wi-Fi firmware and NetworkManager support...\n'

sudo dnf install -y \
  iwlwifi-mvm-firmware \
  NetworkManager-wifi

# Driver and service initialization

printf 'Loading the iwlwifi kernel driver...\n'

sudo modprobe iwlwifi

if ! lsmod | awk '$1 == "iwlwifi" { found = 1 } END { exit !found }'; then
  printf 'Error: iwlwifi could not be loaded.\n' >&2
  exit 1
fi

if systemctl is-active --quiet NetworkManager; then
  printf 'Restarting NetworkManager...\n'
  sudo systemctl restart NetworkManager
else
  printf 'Starting NetworkManager...\n'
  sudo systemctl start NetworkManager
fi

if ! systemctl is-active --quiet NetworkManager; then
  printf 'Error: NetworkManager is not active.\n' >&2
  exit 1
fi

# Wi-Fi discovery

wifi_device=$(nmcli --terse --fields DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }')

if [[ -z "${wifi_device}" ]]; then
  printf 'No Wi-Fi interface was detected. Restart the system and try again.\n' >&2
  exit 1
fi

printf 'Enabling Wi-Fi on %s...\n' "${wifi_device}"

nmcli radio wifi on

printf '\n:: Network devices\n\n'
nmcli device status

printf '\n:: Available Wi-Fi networks\n\n'
nmcli device wifi rescan
nmcli device wifi list

printf '\nTo connect, run: nmcli device wifi connect "SSID" --ask\n'
printf 'If Polkit is unavailable, run: sudo nmcli device wifi connect "SSID" --ask\n'
