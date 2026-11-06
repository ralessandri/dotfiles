#!/bin/bash
# This script shows a rofi dmenu with a fixed list of applications and launches the chosen one.

# Desired applications as .desktop filenames (without path).
# Find the exact names with: find /usr/share/applications ~/.local/share/applications -iname "*firefox*"
application_ids=(
  "org.mozilla.firefox.desktop"
  "com.vivaldi.Vivaldi.desktop"
  "org.chromium.Chromium.desktop"
)

# Standard locations where .desktop files can live
search_dirs=(
  "$HOME/.local/share/applications"
  "/usr/local/share/applications"
  "/usr/share/applications"
  "/var/lib/flatpak/exports/share/applications"
  "$HOME/.local/share/flatpak/exports/share/applications"
)

# Build a map of display name -> .desktop file path
declare -A menu

for id in "${application_ids[@]}"; do
  for dir in "${search_dirs[@]}"; do
    file="$dir/$id"
    if [ -f "$file" ]; then
      # Extract the localized Name= entry from the .desktop file
      name=$(grep "^Name=" "$file" | head -1 | cut -d= -f2-)
      menu["$name"]="$file"
      break
    fi
  done
done

# Show selection menu using rofi
selection_status=0
choice=$(
  printf '%s\n' "${!menu[@]}" |
    rofi -dmenu \
      -kb-custom-1 'Alt+Return' \
      -theme-str "window { width: 300px; }" \
      -theme-str "listview { lines: ${#menu[@]}; }" \
      -theme-str "inputbar { enabled: false; }"
) || selection_status=$?

# Exit if nothing was selected
[ -z "$choice" ] && exit 0
[[ $selection_status -eq 0 || $selection_status -eq 10 ]] || exit 0

# Get the full path to the chosen .desktop file
desktop_file="${menu[$choice]}"

# Extract Exec= line and strip field codes (%f, %u, %U, etc.)
exec_cmd=$(grep "^Exec=" "$desktop_file" | head -1 | cut -d= -f2- | sed 's/%[a-zA-Z]//g')

# Prefer the browser's own private-window desktop action when available.
if [[ $selection_status -eq 10 ]]; then
  private_exec=$(awk '
    $0 == "[Desktop Action new-private-window]" { in_action = 1; next }
    in_action && /^\[/ { exit }
    in_action && /^Exec=/ { sub(/^Exec=/, ""); print; exit }
  ' "$desktop_file")

  if [[ -n "$private_exec" ]]; then
    exec_cmd=$(printf '%s\n' "$private_exec" | sed 's/%[a-zA-Z]//g')
  else
    case "${desktop_file##*/}" in
    org.mozilla.firefox.desktop) exec_cmd="$exec_cmd --private-window" ;;
    com.vivaldi.Vivaldi.desktop | org.chromium.Chromium.desktop) exec_cmd="$exec_cmd --incognito" ;;
    esac
  fi
fi

# Execute the command
exec $exec_cmd
