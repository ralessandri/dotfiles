#!/usr/bin/env bash

set -euo pipefail

# Helpers

_die() {
  printf 'network-connection: %s\n' "$1" >&2
  exit 1
}

_usage() {
  cat <<'EOF'
Usage: network-connection.sh COMMAND [ARGUMENTS]

Manage NetworkManager connection profiles.

Commands:
  list                                    List saved connections.
  active                                  List active connections.
  status                                  Show device status.
  show CONNECTION                         Show connection details.
  up CONNECTION                           Activate a connection.
  down CONNECTION                         Deactivate a connection.
  dhcp CONNECTION                         Use automatic IPv4 addressing.
  static CONNECTION ADDRESS/PREFIX [GATEWAY]
                                          Set a static IPv4 address, keeping the current gateway if omitted.
  dns CONNECTION DNS...                   Set IPv4 DNS servers.
  dns-auto CONNECTION                     Use automatic IPv4 DNS.
  route-add CONNECTION NETWORK/PREFIX [GATEWAY] [METRIC]
                                          Add an IPv4 route.
  route-del CONNECTION NETWORK/PREFIX [GATEWAY] [METRIC]
                                          Remove an IPv4 route.

Options:
  -h, --help                              Show this help message.

Examples:
  network-connection.sh show LAN
  network-connection.sh static LAN 192.168.10.20/24
  network-connection.sh static LAN 192.168.10.20/24 192.168.10.1
  network-connection.sh dns LAN 1.1.1.1 9.9.9.9
  network-connection.sh route-add LAN 10.20.0.0/16 192.168.10.254
EOF
}

_require_connection() {
  local connection="$1"
  local names

  names="$(nmcli --escape no -t -f NAME connection show)"
  grep -Fxq -- "${connection}" <<<"${names}" ||
    _die "connection not found: ${connection}"
}

_apply_connection() {
  local connection="$1"

  printf 'Applying: %s\n' "${connection}"
  nmcli connection up id "${connection}"
}

# Command dispatch

command_name="${1:-help}"
if (($# > 0)); then
  shift
fi

case "${command_name}" in
help | -h | --help)
  _usage
  exit 0
  ;;
esac

command -v nmcli >/dev/null 2>&1 || _die 'required command not found: nmcli'

case "${command_name}" in
list)
  (($# == 0)) || _die 'usage: network-connection.sh list'
  nmcli -f NAME,TYPE,DEVICE connection show
  ;;
active)
  (($# == 0)) || _die 'usage: network-connection.sh active'
  nmcli -f NAME,TYPE,DEVICE connection show --active
  ;;
status)
  (($# == 0)) || _die 'usage: network-connection.sh status'
  nmcli device status
  ;;
show)
  (($# == 1)) || _die 'usage: network-connection.sh show <connection>'
  _require_connection "$1"
  nmcli -f connection.id,connection.type,GENERAL.DEVICES,connection.autoconnect,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP4.ROUTE connection show id "$1"
  ;;
up)
  (($# == 1)) || _die 'usage: network-connection.sh up <connection>'
  _require_connection "$1"
  nmcli connection up id "$1"
  ;;
down)
  (($# == 1)) || _die 'usage: network-connection.sh down <connection>'
  _require_connection "$1"
  nmcli connection down id "$1"
  ;;
dhcp)
  (($# == 1)) || _die 'usage: network-connection.sh dhcp <connection>'
  connection="$1"
  _require_connection "${connection}"
  nmcli connection modify "${connection}" \
    ipv4.method auto \
    ipv4.addresses '' \
    ipv4.gateway ''
  _apply_connection "${connection}"
  ;;
static)
  (($# == 2 || $# == 3)) || _die 'usage: network-connection.sh static <connection> <address/prefix> [gateway]'
  connection="$1"
  address="$2"
  _require_connection "${connection}"
  modify_args=(ipv4.method manual ipv4.addresses "${address}")
  if (($# == 3)); then
    modify_args+=(ipv4.gateway "$3")
  else
    gateway="$(nmcli -g IP4.GATEWAY connection show id "${connection}")"
    if [[ -n "${gateway}" && "${gateway}" != '--' ]]; then
      modify_args+=(ipv4.gateway "${gateway}")
    fi
  fi
  nmcli connection modify "${connection}" "${modify_args[@]}"
  _apply_connection "${connection}"
  ;;
dns)
  (($# >= 2)) || _die 'usage: network-connection.sh dns <connection> <dns...>'
  connection="$1"
  shift
  _require_connection "${connection}"
  dns_servers="$(printf '%s,' "$@")"
  dns_servers="${dns_servers%,}"
  nmcli connection modify "${connection}" \
    ipv4.ignore-auto-dns yes \
    ipv4.dns "${dns_servers}"
  _apply_connection "${connection}"
  ;;
dns-auto)
  (($# == 1)) || _die 'usage: network-connection.sh dns-auto <connection>'
  connection="$1"
  _require_connection "${connection}"
  nmcli connection modify "${connection}" \
    ipv4.ignore-auto-dns no \
    ipv4.dns ''
  _apply_connection "${connection}"
  ;;
route-add)
  (($# >= 2 && $# <= 4)) ||
    _die 'usage: network-connection.sh route-add <connection> <network/prefix> [gateway] [metric]'
  connection="$1"
  shift
  _require_connection "${connection}"
  route="$*"
  nmcli connection modify "${connection}" +ipv4.routes "${route}"
  _apply_connection "${connection}"
  ;;
route-del)
  (($# >= 2 && $# <= 4)) ||
    _die 'usage: network-connection.sh route-del <connection> <network/prefix> [gateway] [metric]'
  connection="$1"
  shift
  _require_connection "${connection}"
  route="$*"
  nmcli connection modify "${connection}" -ipv4.routes "${route}"
  _apply_connection "${connection}"
  ;;
*)
  _die "unknown command: ${command_name}"
  ;;
esac
