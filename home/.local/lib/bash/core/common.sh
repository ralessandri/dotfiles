#!/bin/sh -e

findPackageManager() {
    for pgm in "$@"; do
        if available "$pgm"; then
            echo "$pgm"
            return 0
        fi
    done

    return 1
}

checkEscalationTool() {
    for tool in "$@"; do
        if available "$tool"; then
          echo "$tool"
          return 0
        fi
    done

    exit 1
}

PACKAGER=$(findPackageManager nala apt-get dnf pacman zypper apk xbps-install eopkg)
ESCALATION_TOOL=$(checkEscalationTool sudo doas)