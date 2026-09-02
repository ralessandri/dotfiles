#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$HOME/.dotfiles/home/.local/lib/bash/core/init.sh"

# Ensure dnf-plugins-core is installed (needed for config-manager)
if ! rpm -q dnf-plugins-core &>/dev/null; then
  print_section "Installing dnf-plugins-core..."
  sudo dnf install -y dnf-plugins-core
  success_message "dnf-plugins-core installed successfully"
fi

# Add Docker CE repository
if [ ! -e /etc/yum.repos.d/docker-ce.repo ]; then
  print_section "Adding Docker repository..."
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  success_message "Docker repository added successfully"
else
  info_message "Docker repository already exists"
fi

# Install Docker CE and its plugins
if ! available docker; then
  print_section "Installing Docker..."
  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  success_message "Docker installed successfully"
else
  info_message "Docker is already installed"
fi

# Enable and start Docker services
print_section "Enabling and starting Docker services..."
sudo systemctl enable --now docker
sudo systemctl enable --now containerd
success_message "Docker and containerd services enabled and started"

# Configure non-root user access to Docker
print_section "Configuring user permissions for Docker..."
if ! getent group docker >/dev/null; then
  sudo groupadd docker
fi

if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  success_message "Added user '$USER' to the 'docker' group"
  info_message "Please log out and log back in, or run 'newgrp docker' for group changes to take effect."
else
  info_message "User '$USER' is already a member of the 'docker' group"
fi
