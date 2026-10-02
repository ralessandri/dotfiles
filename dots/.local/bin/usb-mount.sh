#!/usr/bin/env bash

set -euo pipefail

readonly script_name="$(basename "$0")"

selector='rofi'
interactive=false
declare -a device_records=()

die() {
  local message="$1"

  printf '%s: %s\n' "${script_name}" "${message}" >&2
  if [[ "${interactive}" == true && "${selector}" == rofi ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="usb-mount" --urgency=critical 'Storage action failed' "${message}" || true
  fi
  exit 1
}

usage() {
  cat <<EOF
Usage: ${script_name} [--gum] [COMMAND] [DEVICE]

Mount, unmount, eject, and inspect storage devices with udisksctl.

Commands:
  menu                 Select a mountable device and an action (default).
  list                 List recognized mountable devices.
  status [DEVICE]      Show the status for a device.
  mount [DEVICE]       Mount a device.
  unmount [DEVICE]     Unmount a device.
  eject [DEVICE]       Unmount related devices and safely power off its disk.

Options:
  --gum                Use Gum instead of Rofi for the interactive interface.
  -h, --help           Show this help message.

Examples:
  ${script_name}
  ${script_name} --gum
  ${script_name} mount /dev/sdb1
EOF
}

require_commands() {
  local command

  for command in udisksctl lsblk findmnt jq rofi gum notify-send; do
    command -v "${command}" >/dev/null 2>&1 ||
      die "Required command not found in PATH: ${command}"
  done
}

resolve_disk() {
  local path="$1"

  # The selected lsblk columns produce a flat JSON device list.
  lsblk --json --paths --output PATH,PKNAME,TYPE |
    jq -er --arg path "${path}" '
      .blockdevices[]
      | select(.path == $path)
      | if .type == "disk" then .path else .pkname // empty end
    '
}

system_disk_path() {
  local root_source

  root_source="$(findmnt --noheadings --output SOURCE --target /)"
  # Remove Btrfs's optional [subvolume] suffix before resolving the block device.
  root_source="${root_source%%[*}"
  [[ "${root_source}" == /dev/* ]] || return 1

  resolve_disk "${root_source}"
}

list_mountable_devices() {
  local system_disk

  system_disk="$(system_disk_path)" || die 'Cannot determine the system disk.'

  lsblk --json --paths --output PATH,PKNAME,TYPE,RM,HOTPLUG,SIZE,FSTYPE,LABEL,MOUNTPOINTS |
    jq -r --arg system_disk "${system_disk}" '
      .blockdevices as $devices
      | $devices[]
      | . as $device
      | (if .type == "disk" then .path else .pkname end) as $disk
      | ([
          $devices[]
          | select(.path == $disk)
          | (.rm == true or .rm == 1 or .hotplug == true or .hotplug == 1)
        ] | any) as $ejectable
      | select(
          .path? and
          (.type == "disk" or .type == "part") and
          (
            .type == "part" or
            (.type == "disk" and ([ $devices[] | select(.pkname == $device.path) ] | length == 0))
          ) and
          (.fstype? // "") != "" and
          .fstype != "swap" and
          .fstype != "crypto_LUKS" and
          .fstype != "LVM2_member" and
          .fstype != "linux_raid_member" and
          .path != $system_disk and
          (.pkname // "") != $system_disk
        )
      | [
          .path,
          (.size // "-"),
          (.fstype // "-"),
          (.label // "-"),
          ((.mountpoints // []) | map(select(. != null and . != "")) | join(", ")),
          $disk,
          $ejectable
        ]
      | join("\u001f")
    '
}

load_mountable_devices() {
  local entries_output

  entries_output="$(list_mountable_devices)" || return 1
  device_records=()
  [[ -n "${entries_output}" ]] && mapfile -t device_records <<<"${entries_output}"
}

find_device_record() {
  local device="$1"
  local record
  local path

  for record in "${device_records[@]}"; do
    IFS=$'\x1f' read -r path _ <<<"${record}"
    if [[ "${path}" == "${device}" ]]; then
      printf '%s' "${record}"
      return 0
    fi
  done

  return 1
}

require_device_record() {
  local device="$1"
  local record

  record="$(find_device_record "${device}")" || die "Not an available mountable device: ${device}"
  printf '%s' "${record}"
}

record_field() {
  local record="$1"
  local field="$2"
  local path
  local size
  local filesystem
  local label
  local mountpoint
  local disk
  local ejectable

  IFS=$'\x1f' read -r path size filesystem label mountpoint disk ejectable <<<"${record}"
  case "${field}" in
  path) printf '%s' "${path}" ;;
  size) printf '%s' "${size}" ;;
  filesystem) printf '%s' "${filesystem}" ;;
  label) printf '%s' "${label}" ;;
  mountpoint) printf '%s' "${mountpoint}" ;;
  disk) printf '%s' "${disk}" ;;
  ejectable) printf '%s' "${ejectable}" ;;
  *) die "Unknown device record field: ${field}" ;;
  esac
}

device_label() {
  local record="$1"
  local path
  local size
  local filesystem
  local label
  local mountpoint
  local state='not mounted'

  path="$(record_field "${record}" path)"
  size="$(record_field "${record}" size)"
  filesystem="$(record_field "${record}" filesystem)"
  label="$(record_field "${record}" label)"
  mountpoint="$(record_field "${record}" mountpoint)"
  [[ -n "${mountpoint}" ]] && state="mounted: ${mountpoint}"
  printf '%s | %s | %s | %s | %s' "${path}" "${label}" "${size}" "${filesystem}" "${state}"
}

select_index() {
  local title="$1"
  shift
  local -a labels=("$@")
  local selected_label
  local selected_index
  local index

  ((${#labels[@]} > 0)) || return 2

  case "${selector}" in
  rofi)
    selected_index="$(printf '%s\n' "${labels[@]}" |
      rofi -dmenu -i -p "${title}" -format i)" || return 2
    ;;
  gum)
    # Esc and Ctrl+C return non-zero, matching Rofi's cancellation path.
    selected_label="$(gum choose --header "${title}" "${labels[@]}")" || return 2
    for index in "${!labels[@]}"; do
      if [[ "${labels[${index}]}" == "${selected_label}" ]]; then
        selected_index="${index}"
        break
      fi
    done
    [[ -n "${selected_index:-}" ]] || return 1
    ;;
  *) die "Unknown selector: ${selector}" ;;
  esac

  [[ "${selected_index}" =~ ^[0-9]+$ ]] || return 1
  [[ "${selected_index}" -lt "${#labels[@]}" ]] || return 1
  printf '%s' "${selected_index}"
}

select_device() {
  local record
  local selected_index
  local -a labels=()
  local -a paths=()

  ((${#device_records[@]} > 0)) || die 'No mountable storage devices found.'
  for record in "${device_records[@]}"; do
    labels+=("$(device_label "${record}")")
    paths+=("$(record_field "${record}" path)")
  done

  selected_index="$(select_index 'Storage device' "${labels[@]}")" || return
  printf '%s' "${paths[${selected_index}]}"
}

select_action() {
  local record="$1"
  local mountpoint
  local ejectable
  local selected_index
  local -a action_labels=()
  local -a action_values=()

  mountpoint="$(record_field "${record}" mountpoint)"
  ejectable="$(record_field "${record}" ejectable)"
  if [[ -n "${mountpoint}" ]]; then
    action_labels=('Unmount' 'Status')
    action_values=('unmount' 'status')
  else
    action_labels=('Mount' 'Status')
    action_values=('mount' 'status')
  fi
  if [[ "${ejectable}" == true ]]; then
    action_labels+=('Eject')
    action_values+=('eject')
  fi

  selected_index="$(select_index 'Action' "${action_labels[@]}")" || return
  printf '%s' "${action_values[${selected_index}]}"
}

notify_result() {
  local urgency="$1"
  local title="$2"
  local message="$3"

  if [[ "${interactive}" == true && "${selector}" == rofi ]]; then
    if ! notify-send --app-name="usb-mount" --urgency="${urgency}" "${title}" "${message}"; then
      printf '%s: %s\n' "${title}" "${message}" >&2
    fi
  elif [[ "${urgency}" == critical ]]; then
    printf '%s: %s\n' "${title}" "${message}" >&2
  else
    printf '%s: %s\n' "${title}" "${message}"
  fi
}

run_udisksctl() {
  local success_title="$1"
  local success_message="$2"
  shift 2
  local output

  if output="$(udisksctl "$@" 2>&1)"; then
    notify_result normal "${success_title}" "${success_message}"
    return 0
  fi

  notify_result critical 'Storage action failed' "${output}"
  return 1
}

mount_device() {
  local device="$1"

  run_udisksctl 'Storage device mounted' "${device}" mount -b "${device}"
}

unmount_device() {
  local device="$1"

  run_udisksctl 'Storage device unmounted' "${device}" unmount -b "${device}"
}

confirm_eject() {
  local selected_index
  local -a labels=('Cancel' 'Eject')
  local -a values=('cancel' 'eject')

  selected_index="$(select_index 'Confirm eject?' "${labels[@]}")" || return 1
  [[ "${values[${selected_index}]}" == eject ]]
}

eject_device() {
  local device="$1"
  local record="$2"
  local disk
  local ejectable
  local candidate_record
  local candidate_device
  local mountpoint

  disk="$(record_field "${record}" disk)"
  ejectable="$(record_field "${record}" ejectable)"
  [[ "${ejectable}" == true ]] || die "Eject is available only for removable or hotplug disks: ${disk}"
  # Explicit device invocations are non-interactive so they remain scriptable.
  if [[ "${interactive}" == true ]]; then
    confirm_eject || return
  fi

  for candidate_record in "${device_records[@]}"; do
    [[ "$(record_field "${candidate_record}" disk)" == "${disk}" ]] || continue
    candidate_device="$(record_field "${candidate_record}" path)"
    mountpoint="$(record_field "${candidate_record}" mountpoint)"
    [[ -z "${mountpoint}" ]] || run_udisksctl 'Storage device unmounted' "${candidate_device}" unmount -b "${candidate_device}"
  done

  run_udisksctl 'Storage device ejected' "${disk}" power-off -b "${disk}"
}

show_status() {
  local device="$1"
  local record="$2"
  local mountpoint

  mountpoint="$(record_field "${record}" mountpoint)"
  if [[ -n "${mountpoint}" ]]; then
    notify_result normal 'Storage device status' "${device} is mounted at ${mountpoint}"
  else
    notify_result normal 'Storage device status' "${device} is not mounted"
  fi
}

run_device_action() {
  local action="$1"
  local device="$2"
  local record

  record="$(require_device_record "${device}")"
  case "${action}" in
  mount) mount_device "${device}" ;;
  unmount) unmount_device "${device}" ;;
  eject) eject_device "${device}" "${record}" ;;
  status) show_status "${device}" "${record}" ;;
  *) die "Unknown action: ${action}" ;;
  esac
}

run_menu() {
  local device
  local record
  local action

  device="$(select_device)" || return
  record="$(require_device_record "${device}")"
  action="$(select_action "${record}")" || return
  run_device_action "${action}" "${device}"
}

print_device_list() {
  local record
  local path
  local size
  local filesystem
  local label
  local mountpoint

  for record in "${device_records[@]}"; do
    IFS=$'\x1f' read -r path size filesystem label mountpoint _ <<<"${record}"
    printf '%s\t%s\t%s\t%s\t%s\n' "${path}" "${size}" "${filesystem}" "${label}" "${mountpoint}"
  done
}

main() {
  local command='menu'
  local device=''

  while (($# > 0)); do
    case "$1" in
    --gum)
      selector='gum'
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    menu | list | status | mount | unmount | eject)
      [[ "${command}" == menu ]] || die "Only one command may be specified."
      command="$1"
      ;;
    /dev/*)
      [[ -z "${device}" ]] || die "Only one device may be specified."
      device="$1"
      ;;
    *) die "Unknown argument: $1" ;;
    esac
    shift
  done

  if [[ "${command}" == menu || ("${command}" != list && -z "${device}") ]]; then
    interactive=true
  fi

  require_commands
  load_mountable_devices || die 'Cannot read mountable storage devices.'

  case "${command}" in
  menu) run_menu ;;
  list) print_device_list ;;
  status | mount | unmount | eject)
    [[ -n "${device}" ]] || device="$(select_device)" || return
    run_device_action "${command}" "${device}"
    ;;
  esac
}

main "$@"
