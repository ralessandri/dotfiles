#!/usr/bin/env bash
set -euo pipefail

readonly WEBAPP_PROFILE="Default"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

install_webapp() {
  local name=$1
  local url=$2

  webapp-install.sh --name "$name" --url "$url" --profile "$WEBAPP_PROFILE"
}

webapp_url_for() {
  case $1 in
    ChatGPT) printf '%s' 'https://chatgpt.com' ;;
    Claude) printf '%s' 'https://claude.ai' ;;
    Discord) printf '%s' 'https://discord.com/channels/@me' ;;
    Github) printf '%s' 'https://github.com' ;;
    Youtube) printf '%s' 'https://www.youtube.com' ;;
    *) return 1 ;;
  esac
}

main() {
  require_cmd gum
  require_cmd webapp-install.sh

  local -a webapps=(
    ChatGPT
    Claude
    Discord
    Github
    Youtube
  )

  printf 'Installing Default Webapps...\n'

  local selected_webapps_raw
  if ! selected_webapps_raw=$(
    printf '%s\n' "${webapps[@]}" | gum choose --no-limit --header "Select web apps to install"
  ); then
    printf 'No web apps selected.\n'
    exit 0
  fi

  local -a selected_webapps=()
  mapfile -t selected_webapps <<<"$selected_webapps_raw"

  if ((${#selected_webapps[@]} == 0)); then
    printf 'No web apps selected.\n'
    exit 0
  fi

  local app
  for app in "${selected_webapps[@]}"; do
    install_webapp "$app" "$(webapp_url_for "$app")"
  done

  printf '\nDefault Webapps setup complete.\n'
}

main "$@"
