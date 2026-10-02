#!/bin/bash

browser=$(xdg-settings get default-web-browser)

case $browser in
google-chrome* | com.google.Chrome* | \
  brave* | com.brave.Browser* | \
  microsoft-edge* | com.microsoft.Edge* | \
  opera* | com.opera.Opera* | \
  vivaldi* | com.vivaldi.Vivaldi* | \
  helium* | \
  chromium*) ;;
*) browser="chromium-browser.desktop" ;;
esac

desktop_dirs=(
  "$HOME/.local/share/applications"
  "$HOME/.local/share/flatpak/exports/share/applications"
  "/var/lib/flatpak/exports/share/applications"
  "/usr/local/share/applications"
  "/usr/share/applications"
)

bin=""
for dir in "${desktop_dirs[@]}"; do
  file="$dir/$browser"
  if [[ -f "$file" ]]; then
    bin=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$file" | head -1)
    [[ -n "$bin" ]] && break
  fi
done

# Fallback: native RPM-Chromium on Fedora
[[ -z "$bin" ]] && bin="/usr/lib64/chromium-browser/chromium-browser.sh"

if command -v uwsm >/dev/null 2>&1; then
  exec setsid uwsm-app -- "$bin" --app="$1" "${@:2}"
else
  exec setsid "$bin" --app="$1" "${@:2}"
fi
