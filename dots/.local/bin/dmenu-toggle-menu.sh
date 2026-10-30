#!/usr/bin/env bash
set -euo pipefail

launcher=${1:---rofi}
actions=(struts-on center-focused-column-always)
labels=("Reserve space at screen edges" "Center Focused Column Always")
options=()

for index in "${!actions[@]}"; do
  state=$(niri-action-manager.sh status "${actions[index]}")
  options+=("${labels[index]} [$state]")
done

case $launcher in
--rofi) picker=(rofi -dmenu -p "Niri Toggles" -format i) ;;
--dms) picker=(dms dmenu --size 1 -p "Niri Toggles" --format i) ;;
*)
  printf 'Usage: %s [--rofi|--dms]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

selected=$(printf '%s\n' "${options[@]}" | "${picker[@]}")
[[ -n $selected ]] || exit 0
[[ $selected =~ ^[0-9]+$ && selected -lt ${#actions[@]} ]] || exit 2
niri-action-manager.sh toggle "${actions[selected]}"
