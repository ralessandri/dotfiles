# Display the 16 classic ANSI color slots
ansi_colors() {
  local i
  local -a ansi_codes=(30 31 32 33 34 35 36 37 90 91 92 93 94 95 96 97)
  local -a color_names=(
    black red green yellow blue magenta cyan gray
    darkgray lightred lightgreen lightyellow lightblue lightmagenta lightcyan white
  )

  for i in {0..15}; do
    printf '\e[38;5;%sm Slot %2s | ANSI %s | %s\e[0m\n' \
      "$i" "$i" "${ansi_codes[i]}" "${color_names[i]}"
  done
}

ansi16() {
  for i in {0..15}; do
    printf '\e[48;5;%dm %3d \e[0m' "$i" "$i"
    (((i + 1) % 8 == 0)) && echo
  done
}

ansi256() {
  for i in {0..255}; do
    printf '\e[48;5;%dm %3d \e[0m' "$i" "$i"
    (((i + 1) % 16 == 0)) && echo
  done
}
