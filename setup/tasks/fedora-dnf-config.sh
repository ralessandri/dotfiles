#!/usr/bin/env bash
set -euo pipefail

printf 'Configuring DNF...\n'

sudo mkdir -p /etc/dnf/libdnf5.conf.d

sudo tee /etc/dnf/libdnf5.conf.d/90-local.conf >/dev/null <<'EOF'
[main]
max_parallel_downloads=10
fastestmirror=True
defaultyes=True
EOF

printf 'Installing DNF plugins...\n'

sudo dnf install -y dnf5-plugins

printf '\nDNF setup complete.\n'

# dnf --dump-main-config |
#   grep -E '^(max_parallel_downloads|fastestmirror|defaultyes) ='
