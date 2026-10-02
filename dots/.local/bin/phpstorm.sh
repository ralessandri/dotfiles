#!/bin/bash

# Path to PhpStorm binary
PHPSTORM_PATH="$HOME/.local/opt/PhpStorm/bin/phpstorm"

# Ensure the script can be run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Check if PhpStorm binary exists and is executable
  if [ -x "$PHPSTORM_PATH" ]; then
    # Check if an argument (file or directory) was provided
    if [ "$1" ]; then
      TARGET="$1"
      # Verify if the provided argument is a directory
      if [ -d "$TARGET" ]; then
        # Open the directory in PhpStorm
        "$PHPSTORM_PATH" "$TARGET" >/dev/null 2>&1 &
      # Verify if the provided argument is a file
      elif [ -f "$TARGET" ]; then
        # Open the file in PhpStorm
        "$PHPSTORM_PATH" "$TARGET" >/dev/null 2>&1 &
      else
        echo "Error: The specified path is neither a file nor a directory: $TARGET"
        exit 1
      fi
    else
      # Launch PhpStorm without any argument if no path is provided
      "$PHPSTORM_PATH" >/dev/null 2>&1 &
    fi
  else
    echo "PhpStorm not found at $PHPSTORM_PATH. Please check the installation."
    exit 1
  fi
fi

