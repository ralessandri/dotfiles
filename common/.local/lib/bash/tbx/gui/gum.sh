#!/usr/bin/env bash
# gum.sh — gum-based menu, colors inherited from utils.sh

# utils.sh provides ANSI codes for printf; gum requires hex or ANSI-256.
# If hex equivalents are defined in ~/.env, those are used,
# otherwise fall back to the Catppuccin Macchiato values behind the ANSI colors.
GUM_BLUE=${PASTEL_BLUE_HEX:-"#8aadf4"}     # Catppuccin Blue
GUM_YELLOW=${PASTEL_YELLOW_HEX:-"#eed49f"} # Catppuccin Yellow
GUM_GREEN=${PASTEL_GREEN_HEX:-"#a6da95"}   # Catppuccin Green
GUM_PINK=${PASTEL_PINK_HEX:-"#f5bde6"}     # Catppuccin Pink

export GUM_CHOOSE_CURSOR_FOREGROUND="$GUM_BLUE"
export GUM_CHOOSE_SELECTED_FOREGROUND="$GUM_GREEN"
export GUM_CHOOSE_HEADER_FOREGROUND="$GUM_YELLOW"
export GUM_CHOOSE_MATCH_FOREGROUND="$GUM_PINK"

export GUM_CONFIRM_PROMPT_FOREGROUND="$GUM_BLUE"
export GUM_CONFIRM_SELECTED_BACKGROUND="$GUM_GREEN"
export GUM_CONFIRM_SELECTED_FOREGROUND="#24273a"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$GUM_BLUE"

export GUM_SPIN_SPINNER_FOREGROUND="$GUM_BLUE"
export GUM_SPIN_TITLE_FOREGROUND="$GUM_YELLOW"

gum_header() {
  gum style --foreground "$GUM_BLUE" --border double --border-foreground "$GUM_BLUE" \
    --align center --width 50 --padding "0 2" "🚀 $1"
}

gum_section() {
  gum style --foreground "$GUM_YELLOW" --padding "0 1" "$1"
}

show_menu() {
  local current_dir="$1"
  while true; do
    clear
    gum_header "Linux TBX (Toolbox)"
    #gum style --foreground "$GUM_YELLOW" --faint "(Current: ${current_dir#./})"
    echo

    # Collect subfolders and scripts
    DIRS=$(find "$current_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    FILES=$(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name "*.sh" | sort)
    MENU="$DIRS"$'\n'"$FILES"
    MENU_FORMATTED=$(while IFS= read -r item; do
      [[ -d "$item" ]] && echo "$(basename "$item")/" || echo "$(basename "$item" .sh)"
    done <<<"$MENU")

    CHOICE=$(printf "%s\n.. (Back)\nExit" "$MENU_FORMATTED" |
      gum choose --header="↑↓ navigate · ↵ select · esc back" --height=15)
    # gum returns a non-zero exit code on Esc/Ctrl-C
    EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 || -z "$CHOICE" || "$CHOICE" == "Exit" ]]; then
      gum_section "Goodbye!"
      exit 0
    elif [[ "$CHOICE" == ".. (Back)" ]]; then
      return
    elif [[ "$CHOICE" == */ ]]; then
      show_menu "$current_dir/${CHOICE%/}"
    else
      local script_path="$current_dir/$CHOICE.sh"
      if [[ -x "$script_path" ]]; then
        clear
        gum_header "Running: $CHOICE"
        bash "$script_path"
      else
        error_message "Script not executable or missing: $script_path (chmod +x?)"
      fi
      gum confirm "Press Enter to return" --affirmative="Continue" --negative="Quit" || exit 0
    fi
  done
}
