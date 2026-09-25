#!/usr/bin/env bash
set -euo pipefail

# Configuration

readonly dms_settings_file="${DMS_SETTINGS_FILE:-${HOME}/.config/DankMaterialShell/settings.json}"
readonly usage_message="Usage: $(basename -- "$0") [-b ID|--bar ID] [--json] {list|get KEY|set KEY VALUE|set KEY=VALUE [KEY=VALUE ...]}"
readonly jq_bar_filter='def bar_entry($bar): select(type == "object" and .id == $bar);'
# Match dms-theme-switcher.sh's 0.2-second workaround for DMS's ignored first change.
readonly dms_reload_settle_seconds=0.2
temporary_file=""
bar_id=default
json_output=false

# Helpers

_fail() {
  printf '%s\n' "${1}" >&2
  exit 1
}

_fail_usage() {
  _fail "${1}. ${usage_message}"
}

_print_help() {
  printf '%s\n' "Read or change a DankMaterialShell bar configuration."
  printf '\nUsage:\n  %s\n' "${usage_message}"
  printf '\nCommands:\n'
  printf '  %-25s %s\n' "list" "Show all properties of the selected bar."
  printf '  %-25s %s\n' "get KEY" "Print one property value."
  printf '  %-25s %s\n' "set KEY VALUE" "Set one property."
  printf '  %-25s %s\n' "set KEY=VALUE [...]" "Set several properties together."
  printf '\nOptions:\n'
  printf '  %-25s %s\n' "-b ID, --bar ID" "Select a bar by ID (default: default)."
  printf '  %-25s %s\n' "--json" "Print list as JSON."
  printf '  %-25s %s\n' "-h, --help" "Show this help and exit."
  printf '\nExamples:\n'
  printf '  %s\n' "$(basename -- "$0") get bottomGap"
  printf '  %s\n' "$(basename -- "$0") --bar default set bottomGap=8 squareCorners=false"
}

_cleanup() {
  if [[ -n "${temporary_file}" ]]; then
    rm -f -- "${temporary_file}"
  fi
}

_require_command() {
  command -v "${1}" >/dev/null 2>&1 || _fail "Required command is unavailable: ${1}"
}

_validate_settings() {
  local validation_result

  [[ -f "${dms_settings_file}" ]] || _fail "DMS settings file is unavailable: ${dms_settings_file}"
  [[ -r "${dms_settings_file}" ]] || _fail "DMS settings file is not readable: ${dms_settings_file}"
  validation_result="$(jq -e -r -s '
    if length != 1 or (.[0] | type) != "object" then false
    elif (.[0].barConfigs | type) != "array" then "missing_bar_configs"
    else "valid"
    end
  ' "${dms_settings_file}" 2>/dev/null)" ||
    _fail "DMS settings do not contain one valid JSON object: ${dms_settings_file}"
  if [[ "${validation_result}" == missing_bar_configs ]]; then
    _fail "DMS settings have no barConfigs array: ${dms_settings_file}"
  fi
}

_validate_bar() {
  local bar_id="${1}"
  local bar_count

  bar_count="$(jq -r --arg bar "${bar_id}" "${jq_bar_filter} [.barConfigs[] | bar_entry(\$bar)] | length" "${dms_settings_file}")" ||
    _fail "Unable to read DMS bar configurations."
  case "${bar_count}" in
  0) _fail "DMS bar ID does not exist: ${bar_id}" ;;
  1) ;;
  *) _fail "DMS bar ID is not unique: ${bar_id}" ;;
  esac
}

_validate_property() {
  _validate_properties "${1}" "${2}"
}

_validate_properties() {
  local bar_id="${1}"
  local missing_key
  shift

  missing_key="$(jq -r --arg bar "${bar_id}" \
    "${jq_bar_filter} (.barConfigs[] | bar_entry(\$bar)) as \$entry | [\$ARGS.positional[] | select(. as \$key | \$entry | has(\$key) | not)] | .[0] // empty" \
    "${dms_settings_file}" --args "$@" 2>/dev/null)" ||
    _fail "DMS bar property does not exist: ${1}"
  [[ -z "${missing_key}" ]] || _fail "DMS bar property does not exist: ${missing_key}"
}

_reload_dms_settings() {
  touch "${dms_settings_file}" || _fail "Unable to prepare DMS settings reload: ${dms_settings_file}"

  # DMS ignores its first external change after writing settings itself.
  sleep "${dms_reload_settle_seconds}"
  touch "${dms_settings_file}" || _fail "Unable to reload DMS settings: ${dms_settings_file}"
}

# Domain workflows

_list_properties() {
  local bar_id="${1}"
  local json_output="${2}"

  if [[ "${json_output}" == true ]]; then
    jq --arg bar "${bar_id}" "${jq_bar_filter} .barConfigs[] | bar_entry(\$bar)" "${dms_settings_file}"
  else
    jq -r --arg bar "${bar_id}" \
      "${jq_bar_filter} .barConfigs[] | bar_entry(\$bar) | to_entries[] | \"\(.key): \(.value | tojson)\"" \
      "${dms_settings_file}"
  fi
}

_get_property() {
  local bar_id="${1}"
  local property_key="${2}"

  _validate_property "${bar_id}" "${property_key}"
  jq -r --arg bar "${bar_id}" --arg key "${property_key}" \
    "${jq_bar_filter} .barConfigs[] | bar_entry(\$bar) | .[\$key] | if type == \"string\" then . else tojson end" \
    "${dms_settings_file}"
}

_add_update() {
  jq -cn '
    reduce range(0; ($ARGS.positional | length); 2) as $index ({};
      ($ARGS.positional[$index]) as $key |
      ($ARGS.positional[$index + 1]) as $value |
      . + {($key): (
        if $value == "true" then true
        elif $value == "false" then false
        elif ($value | test("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")) then ($value | tonumber)
        else $value
        end
      )}
    )
  ' --args "$@"
}

_set_properties() {
  local bar_id="${1}"
  local assignment
  local property_key
  local property_value
  local settings_dir
  local updates_json
  local -a update_keys=()
  local -a update_pairs=()

  shift
  [[ "$#" -gt 0 ]] || _fail_usage "Missing property and value"
  if [[ "${1}" == *=* ]]; then
    for assignment in "$@"; do
      [[ "${assignment}" == *=* ]] || _fail "Expected KEY=VALUE: ${assignment}"
      property_key="${assignment%%=*}"
      property_value="${assignment#*=}"
      [[ -n "${property_key}" ]] || _fail "A property key must not be empty."
      update_keys+=("${property_key}")
      update_pairs+=("${property_key}" "${property_value}")
    done
  else
    [[ "$#" -eq 2 ]] || _fail_usage "Expected KEY VALUE"
    [[ -n "${1}" ]] || _fail "A property key must not be empty."
    update_keys+=("${1}")
    update_pairs+=("${1}" "${2}")
  fi
  _validate_properties "${bar_id}" "${update_keys[@]}"
  updates_json="$(_add_update "${update_pairs[@]}")" || _fail "Unable to prepare DMS bar update."

  [[ ! -L "${dms_settings_file}" ]] || _fail "DMS settings file must not be a symbolic link: ${dms_settings_file}"
  settings_dir="$(dirname -- "${dms_settings_file}")"
  [[ -w "${settings_dir}" ]] || _fail "DMS settings directory is not writable: ${settings_dir}"
  temporary_file="$(mktemp "${settings_dir}/.settings.json.XXXXXX")" ||
    _fail "Unable to create temporary DMS settings file in: ${settings_dir}"
  chown --reference="${dms_settings_file}" "${temporary_file}" ||
    _fail "Unable to preserve DMS settings ownership."
  chmod --reference="${dms_settings_file}" "${temporary_file}" ||
    _fail "Unable to preserve DMS settings permissions."

  jq --arg bar "${bar_id}" --argjson updates "${updates_json}" "${jq_bar_filter}
    if ([.barConfigs[] | bar_entry(\$bar)] | length) != 1 then
      error(\"bar ID changed during update\")
    elif (.barConfigs[] | bar_entry(\$bar) | ([\$updates | keys[]] - (keys))) != [] then
      error(\"bar properties changed during update\")
    else
      .barConfigs |= map(if ([bar_entry(\$bar)] | length) == 1 then . + \$updates else . end)
    end
  " "${dms_settings_file}" >"${temporary_file}" 2>/dev/null ||
    _fail "Unable to build updated DMS settings."
  jq -e -s 'length == 1 and (.[0] | type == "object")' "${temporary_file}" >/dev/null 2>&1 ||
    _fail "Updated DMS settings are not valid JSON."
  mv -- "${temporary_file}" "${dms_settings_file}" || _fail "Unable to replace DMS settings: ${dms_settings_file}"
  temporary_file=""
  _reload_dms_settings
}

# Option parsing and command dispatch

_main() {
  local command_name

  while [[ "$#" -gt 0 ]]; do
    case "${1}" in
    -h | --help)
      [[ "$#" -eq 1 ]] || _fail_usage "Unexpected help arguments"
      _print_help
      return
      ;;
    -b | --bar)
      [[ "$#" -ge 2 && -n "${2}" ]] || _fail_usage "Missing bar ID"
      bar_id="${2}"
      shift 2
      ;;
    --json)
      json_output=true
      shift
      ;;
    list | get | set)
      command_name="${1}"
      shift
      break
      ;;
    *) _fail_usage "Unknown option or command: ${1}" ;;
    esac
  done

  if [[ -z "${command_name:-}" ]]; then
    _print_help
    return
  fi
  # Accept --json before or after list so both option orders work.
  if [[ "${command_name}" == list ]]; then
    if [[ "$#" -eq 1 && "${1}" == --json ]]; then
      json_output=true
      shift
    fi
    [[ "$#" -eq 0 ]] || _fail_usage "Unexpected list arguments"
  else
    [[ "${json_output}" == false ]] || _fail "--json is only available with list."
  fi

  _require_command jq
  _validate_settings
  _validate_bar "${bar_id}"

  case "${command_name}" in
  list) _list_properties "${bar_id}" "${json_output}" ;;
  get)
    [[ "$#" -eq 1 && -n "${1}" ]] || _fail_usage "Expected one property key"
    _get_property "${bar_id}" "${1}"
    ;;
  set) _set_properties "${bar_id}" "$@" ;;
  esac
}

trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
_main "$@"
