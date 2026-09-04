#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
  printf 'Adding Docker repository...\n'

  sudo dnf config-manager addrepo \
    --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
fi

printf 'Installing Docker...\n'

sudo dnf install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

printf 'Enabling Docker socket...\n'

sudo systemctl disable --now docker.service
sudo systemctl enable --now docker.socket

if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"

  printf '\nDocker installed successfully.\n'
  printf 'Log out and back in to activate docker group membership.\n'
else
  printf '\nDocker installed successfully.\n'
fi
