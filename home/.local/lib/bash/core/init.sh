#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Load colors and path settings from ~/.env if available, else use defaults
if [[ -f ~/.env ]]; then
  source ~/.env
fi

source "$SCRIPT_DIR/_utils.sh"
source "$SCRIPT_DIR/_common.sh"
