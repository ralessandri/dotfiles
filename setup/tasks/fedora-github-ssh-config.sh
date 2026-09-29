#!/usr/bin/env bash
set -euo pipefail

die() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

case "${1:-}" in
'') ;;
-h | --help)
  printf 'Usage: %s [-h|--help]\n' "${0##*/}"
  printf 'Log in with gh and register ~/.ssh/id_ed25519 on GitHub.\n'
  exit 0
  ;;
*) die "Unknown option: $1" 2 ;;
esac

command -v gh >/dev/null || die 'gh is not installed.'
command -v ssh-keygen >/dev/null || die 'ssh-keygen is not installed.'
[[ -n "${HOME:-}" ]] || die 'HOME is not set.'

key="${HOME}/.ssh/id_ed25519"

# ssh-keygen creates ~/.ssh with 0700 if it is missing
[[ -e "${key}" ]] || ssh-keygen -t ed25519 -f "${key}"
[[ -e "${key}.pub" ]] || ssh-keygen -y -f "${key}" >"${key}.pub"

gh auth status --hostname github.com >/dev/null 2>&1 ||
  gh auth login --hostname github.com --git-protocol ssh --web \
    --skip-ssh-key --scopes admin:public_key

list_keys() { gh api --hostname github.com --paginate /user/keys --jq '.[].key'; }

# Listing fails when the token lacks the scope: refresh once, then retry
remote="$(list_keys)" || {
  gh auth refresh --hostname github.com --scopes admin:public_key
  remote="$(list_keys)"
}

material="$(awk '{print $2}' "${key}.pub")"
if [[ "${remote}" == *"${material}"* ]]; then
  printf 'SSH key is already registered.\n'
else
  gh ssh-key add "${key}.pub" --type authentication
fi

gh config set git_protocol ssh --host github.com
