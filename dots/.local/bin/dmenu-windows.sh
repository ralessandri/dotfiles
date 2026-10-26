#!/usr/bin/env bash
set -euo pipefail

launcher=${1:---rofi}
mapfile -t windows < <(niri msg --json windows | jq -r '.[] | "\(.id)\t\(.app_id // "Window") [\(.title // "Untitled")]"')
[[ ${#windows[@]} -gt 0 ]] || exit 0

case $launcher in
--rofi) picker=(rofi -dmenu -p "Niri Windows" -format i) ;;
--dms) picker=(dms dmenu --size 1 -p "Niri Windows" --format i) ;;
*)
  printf 'Usage: %s [--rofi|--dms]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

selected=$(printf '%s\n' "${windows[@]#*$'\t'}" | "${picker[@]}")
[[ -n $selected ]] || exit 0
niri msg action focus-window --id "${windows[selected]%%$'\t'*}"
