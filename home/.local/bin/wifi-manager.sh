#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C.UTF-8

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly APP_ID='wifi-manager'
readonly DEFAULT_FZF_COLOR='fg:#dfe3e7,bg:-1,fg+:#00344a,bg+:#90cef4,hl:#90cef4,hl+:#00344a,info:#90cef4,prompt:#90cef4,pointer:#90cef4,marker:#90cef4,spinner:#90cef4,header:#dfe3e7,border:#90cef4,separator:#90cef4,preview-border:#90cef4,preview-fg:#dfe3e7,preview-bg:-1'

# Parse nmcli's escaped colon-separated fields.
readonly AWK_PARSER=$(
  cat <<'AWK_EOF'
function parse_escaped(line, fields,    i, character, escaped, field, count) {
  count = 1
  field = ""
  escaped = 0
  for (i = 1; i <= length(line); i++) {
    character = substr(line, i, 1)
    if (escaped) {
      field = field character
      escaped = 0
    } else if (character == "\\") {
      escaped = 1
    } else if (character == ":") {
      fields[count++] = field
      field = ""
    } else {
      field = field character
    }
  }
  fields[count] = field
  return count
}

mode == "networks" {
  field_count = parse_escaped($0, fields)
  if (field_count < 8) next
  marker = (fields[1] == "*") ? "*" : " "
  ssid = fields[2]
  signal = fields[3]
  rate = fields[5]
  security = fields[6]
  channel = fields[7]
  bssid = fields[8]
  printf "%s\t%-32s\t%3s%%\t%-10s\t%-10s\t%s\t%s\t%s\n", marker, ssid, signal, rate, security, channel, bssid, ssid
  next
}

mode == "active_check" {
  field_count = parse_escaped($0, fields)
  if (field_count < 2) next
  if (fields[1] == "*" && fields[2] == ENVIRON["WIFI_MANAGER_SELECTED_SSID"]) {
    found = 1
  }
  next
}

mode == "active_device" {
  field_count = parse_escaped($0, fields)
  if (field_count >= 3 && fields[1] == "*" &&
      toupper(fields[2]) == toupper(ENVIRON["WIFI_MANAGER_SELECTED_BSSID"])) {
    print fields[3]
    exit
  }
  next
}

mode == "connection_list" {
  field_count = parse_escaped($0, fields)
  if (field_count < 3) next
  printf "%s\t%s\t%s\n", fields[2], fields[3], fields[1]
  next
}

mode == "saved_matches" {
  field_count = parse_escaped($0, fields)
  if (field_count >= 4 && (fields[3] == "wifi" || fields[3] == "802-11-wireless") && fields[4] == ssid) {
    printf "%s\t%s\n", fields[2], fields[1]
  }
  next
}

END {
  if (mode == "active_check") {
    exit (found ? 0 : 1)
  }
}
AWK_EOF
)

show_help() {
  cat <<'EOF'
Usage: wifi-manager.sh [--terminal TERMINAL]

Manage NetworkManager Wi-Fi connections with fzf.

Keys (for the highlighted network; text search is disabled):
  Up/Down  Select network
  c        Connect
  d        Disconnect
  f        Forget saved profiles (with confirmation)
  i        Show Wi-Fi QR code (connected access point)
  r        Rescan
  Esc      Close

Options:
  --terminal TERMINAL  Use a terminal (default: auto; known terminals get
                       app-specific arguments, others use -e).
  --color COLORS       Override the fzf color specification. The value from
                       WIFI_MANAGER_FZF_COLOR is forwarded automatically.
  -h, --help           Show this help message.
EOF
}

die() {
  printf 'wifi-manager: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_in_terminal() {
  local terminal="$1"
  shift
  local -a relaunch_args=("$@")

  if [[ "$terminal" == auto ]]; then
    for candidate in alacritty wezterm foot "${TERMINAL:-}" x-terminal-emulator; do
      [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null 2>&1 && {
        terminal="$candidate"
        break
      }
    done
  fi

  command -v "$terminal" >/dev/null 2>&1 || die "terminal not found: $terminal"

  case "$terminal" in
  wezterm)
    exec wezterm start --class "$APP_ID" --always-new-process -- "$SCRIPT_PATH" --in-terminal "${relaunch_args[@]}"
    ;;
  foot)
    exec foot --app-id="$APP_ID" "$SCRIPT_PATH" --in-terminal "${relaunch_args[@]}"
    ;;
  alacritty)
    exec alacritty --class "$APP_ID" -e "$SCRIPT_PATH" --in-terminal "${relaunch_args[@]}"
    ;;
  *)
    exec "$terminal" -e "$SCRIPT_PATH" --in-terminal "${relaunch_args[@]}"
    ;;
  esac
}

list_networks() {
  local rescan="$1"
  local output

  if ! output="$(nmcli --terse --escape yes --fields IN-USE,SSID,SIGNAL,BARS,RATE,SECURITY,CHAN,BSSID device wifi list --rescan "$rescan")"; then
    printf 'Unable to list Wi-Fi networks. Is NetworkManager running?\n' >&2
    return 1
  fi

  awk -v mode=networks "$AWK_PARSER" <<<"$output" |
    awk -F $'\t' '{ print ($1 == "*" ? 0 : 1) "\t" $0 }' |
    LC_ALL=C sort -t $'\t' -k1,1n -k3,3 |
    cut -f2-
}

select_network() {
  local fzf_color="$1"
  local selected_line
  local reload_command
  local status_text='Scanning...'
  local ready_text='Ready'
  local header_hint='c: connect | d: disconnect | f: forget | i: QR code | r: rescan'
  local header
  local header_ready

  header="* connected | Up/Down: select | Esc: close | Status: ${status_text}"$'\n'"${header_hint}"
  header_ready="* connected | Up/Down: select | Esc: close | Status: ${ready_text}"$'\n'"${header_hint}"

  printf -v reload_command '%q ' "$SCRIPT_PATH" --list yes --color "$fzf_color" --terminal "$terminal"
  reload_command="${reload_command% }"

  if ! selected_line="$(
    list_networks auto |
      fzf \
        --ansi \
        --no-sync \
        --no-input \
        --disabled \
        --no-sort \
        --no-multi \
        --no-print-query \
        --no-select-1 \
        --no-exit-0 \
        --no-expect \
        --expect=c,d,f,i \
        --color="$fzf_color" \
        --delimiter=$'\t' \
        --header="$header" \
        --bind="load:change-header($header_ready)" \
        --bind="r:change-header($header)+reload($reload_command)" \
        --bind='enter:ignore,double-click:ignore' \
        --with-shell='bash -c' \
        --layout=reverse \
        --preview='nmcli --colors no --fields SSID,BSSID,SIGNAL,RATE,SECURITY,CHAN device wifi list bssid {7} --rescan no' \
        --preview-label='Network details' \
        --preview-label-pos='bottom' \
        --preview-window='down:45%:wrap' \
        --with-nth=1,2,3,4,5,6,7
  )"; then
    return 1
  fi

  [[ -n "$selected_line" ]] || return 1
  # Return the shortcut, BSSID and unpadded SSID.
  awk -F $'\t' '
    NR == 1 { key = $0; next }
    NR == 2 && key ~ /^[cdfi]$/ && NF >= 8 {
      printf "%s\t%s\t%s\n", key, $7, $8
      valid = 1
    }
    END { exit !valid }
  ' <<<"$selected_line"
}

network_is_connected() {
  local ssid="$1"
  local output

  output="$(nmcli --terse --escape yes --fields IN-USE,SSID device wifi list --rescan no)" || return 1
  # Pass the literal SSID to awk through the environment.
  WIFI_MANAGER_SELECTED_SSID="$ssid" awk -v mode=active_check "$AWK_PARSER" <<<"$output"
}

wait_for_connection() {
  local ssid="$1"
  local attempt
  for attempt in {1..12}; do
    network_is_connected "$ssid" && return 0
    sleep 0.5
  done
  return 1
}

saved_connections_for_ssid() {
  local ssid="$1"
  local profiles
  local profile_uuid profile_type profile_name profile_ssid

  if ! profiles="$(nmcli --terse --escape yes --fields NAME,UUID,TYPE connection show)"; then
    return 1
  fi

  while IFS=$'\t' read -r profile_uuid profile_type profile_name; do
    [[ -n "$profile_uuid" ]] || continue
    case "$profile_type" in
    wifi | 802-11-wireless) ;;
    *) continue ;;
    esac

    # Read each Wi-Fi profile's SSID without escaping.
    if ! profile_ssid="$(nmcli --terse --escape no --get-values 802-11-wireless.ssid connection show uuid "$profile_uuid")"; then
      printf 'Unable to read saved profile %s.\n' "$profile_name" >&2
      return 1
    fi
    [[ "$profile_ssid" == "$ssid" ]] || continue
    printf '%s\t%s\n' "$profile_uuid" "$profile_name"
  done < <(awk -v mode=connection_list "$AWK_PARSER" <<<"$profiles")
}

run_connect_command() {
  local ask="$1"
  shift
  if [[ "$ask" == true ]]; then
    nmcli --ask "$@" 2>&1
  else
    nmcli "$@" 2>&1
  fi
}

retry_connection() {
  local ssid="$1"
  local ask="$2"
  shift 2
  local output answer

  while true; do
    if output="$(run_connect_command "$ask" "$@")"; then
      printf '%s\n' "$output"
      wait_for_connection "$ssid" || true
      return 0
    fi

    printf 'Connection retry failed:\n%s\n' "$output"
    read -r -p 'Try again? [y/N] ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 1
  done
}

connect_network() {
  local ssid="$1"
  local bssid="${2:-}"
  local saved_connections
  local profile_uuid
  local -a nmcli_cmd
  local output
  local answer

  if ! saved_connections="$(saved_connections_for_ssid "$ssid")"; then
    printf 'Unable to check saved connections for %s.\n' "$ssid" >&2
    return 1
  fi

  if [[ -n "$saved_connections" ]]; then
    profile_uuid="${saved_connections%%$'\t'*}"
    nmcli_cmd=(connection up uuid "$profile_uuid")
    [[ -n "$bssid" ]] && nmcli_cmd+=(ap "$bssid")
    printf 'Activating saved connection for %s...\n' "$ssid"
  else
    nmcli_cmd=(device wifi connect "$ssid")
    if [[ -n "$bssid" ]]; then
      nmcli_cmd+=(bssid "$bssid")
    fi
    printf 'Connecting to %s...\n' "$ssid"
  fi

  if output="$(run_connect_command false "${nmcli_cmd[@]}")"; then
    printf '%s\n' "$output"
    wait_for_connection "$ssid" || printf 'Connection command succeeded, but activation is still pending.\n' >&2
    return 0
  fi

  printf 'Connection failed:\n%s\n' "$output"
  if [[ -n "$saved_connections" ]]; then
    read -r -p 'Try activating the saved connection again? [y/N] ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 1
    retry_connection "$ssid" false "${nmcli_cmd[@]}"
    return $?
  fi

  read -r -p 'Retry and ask for the Wi-Fi password? [y/N] ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 1
  retry_connection "$ssid" true "${nmcli_cmd[@]}"
}

connected_device_for_bssid() {
  local bssid="$1"
  local output

  output="$(nmcli --colors no --terse --escape yes --fields IN-USE,BSSID,DEVICE device wifi list --rescan no)" || return 1
  WIFI_MANAGER_SELECTED_BSSID="$bssid" awk -v mode=active_device "$AWK_PARSER" <<<"$output"
}

disconnect_network() {
  local bssid="$1"
  local device

  device="$(connected_device_for_bssid "$bssid")" || return 1
  if [[ -z "$device" ]]; then
    printf 'The selected access point is not connected.\n'
    return 0
  fi
  nmcli device disconnect "$device"
}

show_connection_status() {
  local device address
  device="$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }')" || true
  [[ -n "$device" ]] || return 0
  address="$(nmcli -g IP4.ADDRESS device show "$device" 2>/dev/null | head -n1)" || true
  printf 'Active device: %s' "$device"
  [[ -n "$address" ]] && printf ' | IP: %s' "$address"
  printf '\n'
}

forget_network() {
  local ssid="$1"
  local profiles
  local answer
  local profile
  local profile_uuid
  local profile_name
  local -a profiles_to_delete=()

  if ! profiles="$(saved_connections_for_ssid "$ssid")"; then
    printf 'Unable to read saved connections.\n' >&2
    return 1
  fi

  while IFS=$'\t' read -r profile_uuid profile_name; do
    [[ -n "$profile_uuid" ]] || continue
    profiles_to_delete+=("$profile_uuid"$'\t'"$profile_name")
  done <<<"$profiles"

  if ((${#profiles_to_delete[@]} == 0)); then
    printf 'No saved connection found for %s.\n' "$ssid"
    return 0
  fi

  printf 'Saved connection profiles for %s:\n' "$ssid"
  printf '  %s\n' "${profiles_to_delete[@]##*$'\t'}"
  read -r -p "Forget saved connection '$ssid'? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 0

  for profile in "${profiles_to_delete[@]}"; do
    profile_uuid="${profile%%$'\t'*}"
    profile_name="${profile#*$'\t'}"
    if ! nmcli connection delete uuid "$profile_uuid"; then
      printf 'Unable to forget saved connection %s.\n' "$profile_name" >&2
      return 1
    fi
  done
}

show_wifi_details() {
  local bssid="$1"
  local device

  device="$(connected_device_for_bssid "$bssid")" || return 1
  if [[ -z "$device" ]]; then
    printf 'Connect to the selected access point first to show its Wi-Fi QR code.\n'
    return 0
  fi

  # Render the Wi-Fi QR code with explicit foreground and background colors.
  if ! nmcli --colors yes dev wifi show-password ifname "$device"; then
    printf 'Unable to show the Wi-Fi QR code.\n' >&2
    return 1
  fi
}

terminal="${WIFI_MANAGER_TERMINAL:-auto}"
in_terminal=false
fzf_color="${WIFI_MANAGER_FZF_COLOR:-$DEFAULT_FZF_COLOR}"
relaunch_args=()

while (($# > 0)); do
  case "$1" in
  --terminal)
    (($# >= 2)) || die '--terminal requires a value'
    terminal="$2"
    relaunch_args+=(--terminal "$2")
    shift 2
    ;;
  --terminal=*)
    terminal="${1#*=}"
    relaunch_args+=(--terminal "$terminal")
    shift
    ;;
  --in-terminal)
    in_terminal=true
    shift
    ;;
  --list)
    (($# >= 2)) || die '--list requires a rescan mode'
    list_networks "$2"
    exit 0
    ;;
  --color)
    (($# >= 2)) || die '--color requires a value'
    fzf_color="$2"
    shift 2
    ;;
  --color=*)
    fzf_color="${1#*=}"
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
done

relaunch_args+=(--color "$fzf_color")

if [[ "$in_terminal" == false ]]; then
  run_in_terminal "$terminal" "${relaunch_args[@]}"
fi

require_command fzf
require_command nmcli

while true; do
  clear || true
  selected_network="$(select_network "$fzf_color")" || exit 0
  IFS=$'\t' read -r action bssid ssid <<<"$selected_network"

  case "$action" in
  c)
    connect_network "$ssid" "$bssid" || true
    show_connection_status || true
    ;;
  d)
    disconnect_network "$bssid" || true
    show_connection_status || true
    ;;
  f)
    forget_network "$ssid" || true
    ;;
  i)
    show_wifi_details "$bssid" || true
    ;;
  esac

  printf '\nPress Enter to return.\n'
  read -r || exit 0
done
