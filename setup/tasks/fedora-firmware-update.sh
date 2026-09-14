#!/usr/bin/env bash
set -euo pipefail

printf 'Installing firmware update tools...\n'

sudo dnf install -y fwupd

printf 'Refreshing firmware metadata...\n'

sudo fwupdmgr refresh --force

printf 'Checking for firmware updates...\n'

if updates_output=$(sudo fwupdmgr get-updates 2>&1); then
  printf '%s\n' "${updates_output}"
else
  updates_status=$?
  printf '%s\n' "${updates_output}"

  if ((updates_status != 2)); then
    printf 'Error: failed to check for firmware updates.\n' >&2
    exit "${updates_status}"
  fi
fi

printf '\nFirmware update check complete.\n'
printf 'Use "sudo fwupdmgr update" to install available updates.\n'
