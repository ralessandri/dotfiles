# Fedora system configuration recipes.

[private]
default:
  @just --list fedora config

# Configure DNF download and default behavior settings.
[group('system')]
dnf:
    ../../tasks/fedora-dnf-config.sh

# Configure GitHub CLI and an SSH authentication key.
[group('development')]
github-ssh:
    ../../tasks/fedora-github-ssh-config.sh
