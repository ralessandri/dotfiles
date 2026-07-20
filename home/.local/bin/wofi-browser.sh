#!/bin/bash
# This script shows a wofi dmenu with a fixed list of applications and launches the chosen one.

# Desired applications as .desktop filenames (without path).
# Find the exact names with: find /usr/share/applications ~/.local/share/applications -iname "*firefox*"
application_ids=(
  "org.mozilla.firefox.desktop"
  "com.vivaldi.Vivaldi.desktop"
  "chromium-browser.desktop"
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

# Show selection menu using wofi
choice=$(printf '%s\n' "${!menu[@]}" | wofi --dmenu -L "${#menu[@]}" -W 300 -jb)

# Exit if nothing was selected
[ -z "$choice" ] && exit 0

# Get the full path to the chosen .desktop file
desktop_file="${menu[$choice]}"

# Extract Exec= line and strip field codes (%f, %u, %U, etc.)
exec_cmd=$(grep "^Exec=" "$desktop_file" | head -1 | cut -d= -f2- | sed 's/%[a-zA-Z]//g')

# Execute the command
exec $exec_cmd
