#!/usr/bin/env bash
set -euo pipefail

# Configuration

readonly script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly script_dir="$(cd -- "$(dirname -- "${script_path}")" && pwd)"
readonly dotfiles_dir="$(cd -- "${script_dir}/../.." && pwd)"
readonly profiles_file="${dotfiles_dir}/.config/theme-profiles/profiles.sh"

# Helpers

_fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

_print_help() {
  printf '%s\n' "Choose the desktop theme profile in Rofi."
  printf '\nUsage: %s [--help]\n' "$(basename -- "$0")"
  printf '\nRun without arguments to open the profile selector.\n'
  printf '\nProfiles:\n'
  printf '  %-26s %s\n' "Strata / Material Vivid" "Uses the fixed Material Vivid DMS theme and prompt."
  printf '  %-26s %s\n' "Wallpaper / Dynamic" "Uses DMS/Matugen wallpaper colors and the ANSI prompt."
  printf '\nEffects:\n'
  printf '%s\n' "  DMS updates immediately; Alacritty stays managed by DMS."
  printf '%s\n' "  The prompt profile applies when a new terminal is opened."
  printf '%s\n' "  Canceling Rofi leaves the active profile unchanged."
  printf '\nExample:\n  %s\n' "$(basename -- "$0")"
}

_require_command() {
  local command_name="$1"

  command -v "${command_name}" >/dev/null 2>&1 || _fail "Required command is unavailable: ${command_name}"
}

_load_profiles() {
  [[ -r "${profiles_file}" ]] || _fail "Theme profile configuration is unavailable: ${profiles_file}"
  source "${profiles_file}"
}

_profile_is_known() {
  local profile_id="$1"

  [[ " ${THEME_PROFILE_IDS[*]} " == *" ${profile_id} "* ]]
}

_profile_id_for_label() {
  local profile_id
  local selected_label="$1"

  for profile_id in "${THEME_PROFILE_IDS[@]}"; do
    if [[ "${THEME_PROFILE_LABELS[${profile_id}]}" == "${selected_label}" ]]; then
      printf '%s\n' "${profile_id}"
      return
    fi
  done

  return 1
}

_validate_profile_assets() {
  local profile_id="$1"
  local prompt_profile="${THEME_PROFILE_PROMPTS[${profile_id}]}"
  local dms_theme_file="${THEME_PROFILE_DMS_FILES[${profile_id}]}"

  [[ -r "${prompt_profile}" ]] || _fail "Theme prompt profile is unavailable: ${prompt_profile}"
  if [[ -n "${dms_theme_file}" && ! -r "${dms_theme_file}" ]]; then
    _fail "DMS theme is unavailable: ${dms_theme_file}"
  fi
}

_validate_dms_ipc() {
  dms ipc call settings get currentThemeName >/dev/null || _fail "DMS IPC is unavailable. Start DMS and try again."
}

# Domain workflows

_select_profile() {
  local profile_id
  local selected_label
  local -a labels=()

  for profile_id in "${THEME_PROFILE_IDS[@]}"; do
    labels+=("${THEME_PROFILE_LABELS[${profile_id}]}")
  done

  if ! selected_label="$(printf '%s\n' "${labels[@]}" | rofi -dmenu -p "Theme profile")"; then
    return 2
  fi
  [[ -n "${selected_label}" ]] || return 2

  _profile_id_for_label "${selected_label}" || return 1
}

_set_dms_setting() {
  local setting_key="$1"
  local setting_value="$2"

  dms ipc call settings set "${setting_key}" "${setting_value}" >/dev/null || _fail "Unable to set DMS setting: ${setting_key}"
}

_apply_dms_profile() {
  local profile_id="$1"
  local dms_theme_file="${THEME_PROFILE_DMS_FILES[${profile_id}]}"
  local current_theme
  local current_category

  dms ipc call settings get currentThemeName >/dev/null || _fail "Unable to read the current DMS theme."
  dms ipc call settings get currentThemeCategory >/dev/null || _fail "Unable to read the current DMS theme category."

  if [[ -n "${dms_theme_file}" ]]; then
    _set_dms_setting customThemeFile "${dms_theme_file}"
  fi
  _set_dms_setting currentThemeName "${THEME_PROFILE_DMS_NAMES[${profile_id}]}"
  _set_dms_setting currentThemeCategory "${THEME_PROFILE_DMS_CATEGORIES[${profile_id}]}"

  current_theme="$(dms ipc call settings get currentThemeName)" || _fail "Unable to verify the DMS theme."
  current_category="$(dms ipc call settings get currentThemeCategory)" || _fail "Unable to verify the DMS theme category."
  printf 'DMS theme settings updated: %s / %s\n' "${current_theme}" "${current_category}"
}

_apply_alacritty_profile() {
  local profile_id="$1"
  local alacritty_config="${HOME}/.config/alacritty/alacritty.toml"

  [[ -r "${alacritty_config}" ]] || _fail "Alacritty configuration is unavailable: ${alacritty_config}"
  printf 'Alacritty palette remains DMS-managed for profile: %s\n' "${profile_id}"
}

_apply_ps1_profile() {
  local profile_id="$1"
  local state_dir
  local temporary_state_file

  state_dir="$(dirname -- "${THEME_PROFILE_STATE_FILE}")"
  mkdir -p "${state_dir}"
  temporary_state_file="$(mktemp "${state_dir}/active-profile.XXXXXX")"
  printf '%s\n' "${profile_id}" >"${temporary_state_file}"
  mv -- "${temporary_state_file}" "${THEME_PROFILE_STATE_FILE}"
  printf 'PS1 profile will apply to new terminals: %s\n' "${profile_id}"
}

# Command dispatch

_main() {
  local profile_id
  local selection_status

  case "${1:-}" in
  --help)
    [[ "$#" -eq 1 ]] || _fail "Usage: $(basename -- "$0") [--help]"
    _print_help
    return
    ;;
  "") ;;
  *)
    _fail "Usage: $(basename -- "$0") [--help]"
    ;;
  esac

  _load_profiles
  _require_command rofi
  _require_command dms

  if profile_id="$(_select_profile)"; then
    :
  else
    selection_status=$?
    [[ "${selection_status}" -eq 2 ]] && return
    _fail "Unable to select a theme profile."
  fi

  _profile_is_known "${profile_id}" || _fail "Unknown theme profile: ${profile_id}"
  _validate_profile_assets "${profile_id}"
  _validate_dms_ipc
  _apply_dms_profile "${profile_id}"
  _apply_alacritty_profile "${profile_id}"
  _apply_ps1_profile "${profile_id}"
}

_main "$@"
