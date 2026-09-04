#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/yum.repos.d/ddev.repo ]]; then
  printf 'Adding DDEV repository...\n'

  sudo tee /etc/yum.repos.d/ddev.repo >/dev/null <<'EOF'
[ddev]
name=ddev
baseurl=https://pkg.ddev.com/yum/
gpgcheck=0
enabled=1
EOF
fi

printf 'Installing DDEV...\n'

sudo dnf install -y --refresh ddev

if ! mkcert -CAROOT >/dev/null 2>&1; then
  printf 'Initializing mkcert...\n'
  mkcert -install
fi

printf '\nDDEV setup complete.\n'
