#!/usr/bin/env bash
set -euo pipefail

printf 'Installing firmware update tools...\n'

sudo dnf install -y fwupd

printf 'Refreshing firmware metadata...\n'

sudo fwupdmgr refresh

printf 'Checking for firmware updates...\n'

sudo fwupdmgr get-updates

printf '\nFirmware update check complete.\n'
printf 'Use "sudo fwupdmgr update" to install available updates.\n'
