#!/usr/bin/env bash
set -euo pipefail

# Configuration

readonly script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly script_dir="$(cd -- "$(dirname -- "${script_path}")" && pwd)"
readonly dotfiles_dir="$(cd -- "${script_dir}/../.." && pwd)"
readonly installed_themes_dir="${HOME}/.config/DankMaterialShell/themes"
readonly custom_themes_dir="${dotfiles_dir}/.config/DankMaterialShell/themes"
readonly dms_settings_file="${HOME}/.config/DankMaterialShell/settings.json"
readonly usage_message="Usage: $(basename -- "$0") [--help|list|active|select]"

# Helpers

_fail() {
  printf '%s\n' "${1}" >&2
  exit 1
}

_print_help() {
  printf '%s\n' "Choose a DankMaterialShell theme."
  printf '\nUsage:\n'
  printf '  %s\n' "$(basename -- "$0")"
  printf '  %s\n' "$(basename -- "$0") list"
  printf '  %s\n' "$(basename -- "$0") active"
  printf '  %s\n' "$(basename -- "$0") select"
  printf '\nOptions:\n'
  printf '  %-16s %s\n' "-h, --help" "Show this help and exit."
  printf '\nCommands:\n'
  printf '  %-16s %s\n' "list" "List all available themes."
  printf '  %-16s %s\n' "active" "Print the currently active theme."
  printf '  %-16s %s\n' "select" "Choose and activate a theme with Gum."
  printf '\nAvailable themes:\n'
  printf '%s\n' "  Dynamic (Auto), installed DMS themes, and local theme.json files."
  printf '%s\n' "  Installed themes are read from ~/.config/DankMaterialShell/themes."
  printf '%s\n' "  Local themes are read from dotfiles/.config/DankMaterialShell/themes."
}

_require_command() {
  local command_name="$1"

  command -v "${command_name}" >/dev/null 2>&1 || _fail "Required command is unavailable: ${command_name}"
}

_require_no_args() {
  [[ "$#" -eq 1 ]] || _fail "${usage_message}"
}

_json_string_field() {
  local json_file="$1"
  local field_name="$2"

  awk -F'"' -v field="${field_name}" '$2 == field { print $4; exit }' "${json_file}"
}

_theme_field_or_dirname() {
  local theme_file="$1"
  local field_name="$2"
  local field_value

  field_value="$(_json_string_field "${theme_file}" "${field_name}")"
  if [[ -n "${field_value}" ]]; then
    printf '%s\n' "${field_value}"
    return
  fi

  basename -- "$(dirname -- "${theme_file}")"
}

_theme_name_from_file() {
  _theme_field_or_dirname "$1" name
}

_theme_id_from_file() {
  _theme_field_or_dirname "$1" id
}

_collect_theme_dir() {
  local theme_dir="$1"
  local type_name="$2"
  local prefix="$3"
  local seen_theme_ids_name="$4"
  local -n theme_ids="${seen_theme_ids_name}"
  local theme_file
  local theme_id
  local theme_name

  shopt -s nullglob
  for theme_file in "${theme_dir}"/*/theme.json; do
    theme_id="$(_theme_id_from_file "${theme_file}")"
    [[ -n "${theme_ids[${theme_id}]:-}" ]] && continue
    theme_ids[${theme_id}]=1
    theme_name="$(_theme_name_from_file "${theme_file}")"
    printf '%s\t%s\t%s · %s\n' "${type_name}" "${theme_file}" "${prefix}" "${theme_name}"
  done
  shopt -u nullglob
}

_theme_entries() {
  local -A seen_theme_ids=()

  printf 'dynamic\t-\tDynamic (Auto)\n'

  # Installed themes take precedence over local themes with the same ID.
  _collect_theme_dir "${installed_themes_dir}" installed "DMS" seen_theme_ids
  _collect_theme_dir "${custom_themes_dir}" local "Local" seen_theme_ids
}

_list_themes() {
  local selection_type
  local selection_value
  local selection_label

  while IFS=$'\t' read -r selection_type selection_value selection_label; do
    printf '%s\n' "${selection_label}"
  done < <(_theme_entries)
}

_setting_value() {
  local setting_key="$1"

  _json_string_field "${dms_settings_file}" "${setting_key}"
}

_print_active_theme() {
  local current_theme
  local custom_theme_file

  current_theme="$(_setting_value currentThemeName)"
  [[ -n "${current_theme}" ]] || _fail "The active DMS theme is unavailable."

  case "${current_theme}" in
  dynamic)
    printf '%s\n' "Dynamic (Auto)"
    ;;
  custom)
    custom_theme_file="$(_setting_value customThemeFile)"
    [[ -r "${custom_theme_file}" ]] || _fail "The active custom theme is unavailable: ${custom_theme_file}"
    printf '%s\n' "$(_theme_name_from_file "${custom_theme_file}")"
    ;;
  *)
    printf '%s\n' "${current_theme}"
    ;;
  esac
}

_set_dms_setting() {
  local setting_key="$1"
  local setting_value="$2"

  dms ipc settings set "${setting_key}" "${setting_value}" >/dev/null || _fail "Unable to set DMS setting: ${setting_key}"
}

_reload_dms_settings() {
  touch "${dms_settings_file}" || _fail "Unable to prepare DMS settings reload: ${dms_settings_file}"

  # DMS ignores its first external change after writing settings itself.
  sleep 0.2
  touch "${dms_settings_file}" || _fail "Unable to reload DMS settings: ${dms_settings_file}"
}

_apply_selection() {
  local selection_type="$1"
  local selection_value="$2"

  case "${selection_type}" in
  dynamic)
    _set_dms_setting currentThemeName dynamic
    _set_dms_setting currentThemeCategory dynamic
    ;;
  installed | local)
    _set_dms_setting customThemeFile "${selection_value}"
    _set_dms_setting currentThemeName custom
    _set_dms_setting currentThemeCategory custom
    ;;
  *)
    _fail "Unknown theme selection type: ${selection_type}"
    ;;
  esac

  _reload_dms_settings
}

# Domain workflows

_select_theme() {
  local selector="$1"
  local selected_index
  local index
  local label_delimiter=$'\x1f'
  local -a labels=()
  local -a selection_types=()
  local -a selection_values=()
  local -a gum_options=()
  local selection_type
  local selection_value
  local selection_label

  while IFS=$'\t' read -r selection_type selection_value selection_label; do
    labels+=("${selection_label}")
    selection_types+=("${selection_type}")
    selection_values+=("${selection_value}")
  done < <(_theme_entries)

  case "${selector}" in
  rofi)
    if ! selected_index="$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "Theme" -format i)"; then
      return 2
    fi
    ;;
  gum)
    for index in "${!labels[@]}"; do
      gum_options+=("${labels[${index}]}${label_delimiter}${index}")
    done
    if ! selected_index="$(gum choose --header "Theme" --label-delimiter "${label_delimiter}" "${gum_options[@]}")"; then
      return 2
    fi
    ;;
  *)
    _fail "Unknown theme selector: ${selector}"
    ;;
  esac
  [[ -n "${selected_index}" ]] || return 2
  [[ "${selected_index}" =~ ^[0-9]+$ ]] || return 1
  [[ "${selected_index}" -lt "${#labels[@]}" ]] || return 1

  printf '%s\t%s\n' "${selection_types[${selected_index}]}" "${selection_values[${selected_index}]}"
}

_validate_theme_directories() {
  [[ -d "${installed_themes_dir}" ]] || _fail "Installed theme directory is unavailable: ${installed_themes_dir}"
  [[ -d "${custom_themes_dir}" ]] || _fail "Local theme directory is unavailable: ${custom_themes_dir}"
}

_validate_dms_settings() {
  [[ -e "${dms_settings_file}" ]] || _fail "DMS settings are unavailable: ${dms_settings_file}"
  [[ -r "${dms_settings_file}" ]] || _fail "DMS settings are not readable: ${dms_settings_file}"
}

_validate_switch_prerequisites() {
  _validate_theme_directories
  _validate_dms_settings
  [[ -w "${dms_settings_file}" ]] || _fail "DMS settings are not writable: ${dms_settings_file}"
}

# Command dispatch

_main() {
  local selection
  local selection_status
  local selector
  local selection_type
  local selection_value

  case "${1:-}" in
  -h | --help)
    _require_no_args "$@"
    _print_help
    return
    ;;
  list)
    _require_no_args "$@"
    _validate_theme_directories
    _list_themes
    return
    ;;
  active)
    _require_no_args "$@"
    _validate_dms_settings
    _print_active_theme
    return
    ;;
  select)
    _require_no_args "$@"
    _require_command dms
    _require_command gum
    _validate_switch_prerequisites
    selector=gum
    ;;
  "")
    _require_command dms
    _require_command rofi
    _validate_switch_prerequisites
    selector=rofi
    ;;
  *)
    _fail "${usage_message}"
    ;;
  esac

  if selection="$(_select_theme "${selector}")"; then
    :
  else
    selection_status=$?
    [[ "${selection_status}" -eq 2 ]] && return
    _fail "Unable to select a theme."
  fi

  IFS=$'\t' read -r selection_type selection_value <<<"${selection}"
  _apply_selection "${selection_type}" "${selection_value}"
}

_main "$@"
