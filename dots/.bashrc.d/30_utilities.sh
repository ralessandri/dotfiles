# Display command-line cheat sheets from cheat.sh
cheat() {
  curl "https://cheat.sh/${1}"
}

# Display the weather forecast from wttr.in
wttr() {
  curl "https://wttr.in/${1}"
}

# Open a directory in Nautilus
open() {
  nautilus "${1:-.}" >/dev/null 2>&1 &
}
