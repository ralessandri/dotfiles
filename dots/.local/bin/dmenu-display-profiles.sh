#!/usr/bin/env bash
set -euo pipefail

# Option parsing
if [[ "${1:-}" == --help ]]; then
  printf 'Usage: %s [--rofi|--dms]\n\n' "${0##*/}"
  printf '%s\n' 'Select a configured DMS display profile.' \
    '  --rofi  Use Rofi (default).' \
    '  --dms   Use DMS dmenu.' \
    '  --help  Show this help.'
  exit 0
fi

if (($# > 1)); then
  printf 'Usage: %s [--rofi|--dms]\n' "${0##*/}" >&2
  exit 2
fi

case "${1:---rofi}" in
--rofi) picker=(rofi -dmenu -p "Display Profiles" -format i) ;;
--dms) picker=(dms dmenu --size 1 -p "Display Profiles" --format i) ;;
*)
  printf 'Usage: %s [--rofi|--dms]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

# Prerequisites
for prerequisite in dms "${picker[0]}"; do
  if ! command -v "${prerequisite}" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "${prerequisite}" >&2
    exit 1
  fi
done

# Profile discovery
profile_list=$(dms ipc call outputs listProfiles)
profiles=()
labels=()
while IFS= read -r line; do
  [[ "${line}" == *' -> '* ]] || continue
  name="${line% -> *}"
  indicator=""
  # DMS appends state flags before the output list; setProfile needs only the name.
  case "${name}" in
  *' [active]' | *' [active,matched]')
    indicator=" ✓"
    name="${name% \[*}"
    ;;
  *' [matched]') name="${name% \[*}" ;;
  esac
  profiles+=("${name}")
  labels+=("${name}${indicator}")
done <<<"${profile_list}"

if ((${#profiles[@]} == 0)); then
  printf 'No DMS display profiles available: %s\n' "${profile_list}" >&2
  exit 1
fi

# Profile selection
if selected=$(printf '%s\n' "${labels[@]}" | "${picker[@]}"); then
  [[ -n "${selected}" ]] || exit 0
else
  status=$?
  [[ "${status}" == 1 ]] && exit 0
  exit "${status}"
fi

if [[ ! "${selected}" =~ ^[0-9]+$ ]] || ((selected < 0 || selected >= ${#profiles[@]})); then
  printf 'Invalid profile selection: %s\n' "${selected}" >&2
  exit 2
fi

# DMS can return an ERROR response with exit status 0.
result=$(dms ipc call outputs setProfile "${profiles[selected]}")
if [[ "${result}" != PROFILE_SET_SUCCESS:* ]]; then
  printf 'Unable to activate display profile: %s\n' "${result}" >&2
  exit 1
fi
printf '%s\n' "${result}"
