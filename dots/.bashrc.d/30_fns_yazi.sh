# Open Yazi and change to the directory selected when it exits.
function yy() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  local cwd

  yazi "$@" --cwd-file="$tmp"
  if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
