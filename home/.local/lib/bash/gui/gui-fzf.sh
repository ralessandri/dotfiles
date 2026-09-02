#!/usr/bin/env bash
show_menu() {
  local current_dir="$1"

  while true; do
    clear
    print_header "Linux TBX (Toolbox)"
    # echo "(Current: ${current_dir#./})"
    echo

    # Collect subfolders and scripts
    DIRS=$(find "$current_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    FILES=$(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name "*.sh" | sort)

    MENU="$DIRS"$'\n'"$FILES"

    MENU_FORMATTED=$(while IFS= read -r item; do
      if [ -d "$item" ]; then
        echo "$(basename "$item")/"
      else
        echo "$(basename "$item" .sh)"
      fi
    done <<<"$MENU")

    CHOICE=$(
      printf "%s\n.. (Back)\nExit" "$MENU_FORMATTED" |
        fzf --prompt="> " \
          --height=15 \
          --layout=reverse \
          --bind 'q:abort' \
          --bind 'left:execute-silent(echo ".. (Back)" > /tmp/fzf_choice; kill -SIGINT $$)'
    )

    if [[ "$CHOICE" == "Exit" || -z "$CHOICE" ]]; then
      print_section "Goodbye!"
      exit 0
    elif [[ "$CHOICE" == ".. (Back)" ]]; then
      return
    elif [[ "$CHOICE" == */ ]]; then
      show_menu "$current_dir/${CHOICE%/}"
    else
      local script_path="$current_dir/$CHOICE.sh"
      if [[ -x "$script_path" ]]; then
        clear
        print_header "Running: $CHOICE"
        bash "$script_path"
      else
        error_message "Script not executable or missing: $script_path"
      fi
      echo "Press Enter to return, or q/Escape to quit..."
      read -rsn1 key
      case "$key" in
      "") # Enter
        echo "Returning..."
        ;;
      q) # q
        echo "Quitting..."
        exit 0
        ;;
      $'\e') # Escape
        echo "Quitting..."
        exit 0
        ;;
      *) # other Key
        echo "Unknown key: $key"
        ;;
      esac
    fi
  done
}
