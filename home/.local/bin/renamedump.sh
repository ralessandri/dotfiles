#!/bin/bash

# Ensure the script can be run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ "$#" -lt 1 ]; then
    echo "Usage: renamedump <file1> [file2 ...]"
    exit 1
  fi

  for file in "$@"; do
    # Check if the file has a valid extension
    if [[ ! "$file" =~ \.sql(\.gz)?$ ]]; then
      echo "Invalid file extension. Only .sql and .sql.gz files are supported."
      continue
    fi

    # Check if the file exists
    if [ ! -e "$file" ]; then
      echo "Error: '$file' does not exist."
      continue
    elif [ ! -f "$file" ]; then
      echo "Error: '$file' is not a file."
      continue
    elif [ ! -w "$file" ]; then
      echo "Error: Insufficient permissions to rename '$file'."
      continue
    fi

    # Prompt user for information
    read -p "Enter the project name (default: $(basename \"$(pwd)\")): " project_name
    read -p "Enter the project type (default: typo3): " project_type
    read -p "Enter the project version (default: 11.5): " project_version

    # Prompt user for environment
    environment=""
    while true; do
      read -p "Enter the environment (1: dev, 2: preview, 3: live, default: 1): " environment_choice
      case "$environment_choice" in
      1)
        environment="dev"
        break
        ;;
      2)
        environment="preview"
        break
        ;;
      3)
        environment="live"
        break
        ;;
      "")
        environment="dev"
        break
        ;;
      *) echo "Please enter '1' for dev, '2' for preview, or '3' for live." ;;
      esac
    done

    # Set default values if empty
    DEFAULT_PROJECT_TYPE="typo3"
    DEFAULT_PROJECT_VERSION="11z.5"
    project_name=${project_name:-$(basename "$(pwd)")}
    project_type=${project_type:-$DEFAULT_PROJECT_TYPE}
    project_version=${project_version:-$DEFAULT_PROJECT_VERSION}
    environment=${environment:-dev}

    # Determine the final extension
    final_extension="sql"
    [[ "$file" == *.*.* ]] && final_extension="sql.gz"

    # Prompt user whether to use creation time or not
    use_creation_time=""
    while true; do
      read -p "Do you want to use the creation time of the file? (y/n, default: n): " use_creation_time
      case "$use_creation_time" in
      [Yy]*)
        use_creation_time="yes"
        break
        ;;
      [Nn]*)
        use_creation_time="no"
        break
        ;;
      "")
        use_creation_time="no"
        break
        ;;
      *) echo "Please enter 'y' for yes or 'n' for no." ;;
      esac
    done

    # Get the creation date and time of the file if requested
    creation_date=""
    creation_time=""
    if [ "$use_creation_time" = "yes" ] && command -v stat &>/dev/null; then
      creation_date=$(stat -c "%y" "$file" | cut -d' ' -f1)
      creation_date=$(date -d "$creation_date" +"%Y%m%d")
      creation_time=$(stat -c "%y" "$file" | cut -d' ' -f2 | cut -d'.' -f1)
      creation_time=$(date -d "$creation_time" +"%H%M%S")
    fi

    # Current date and time
    current_date=$(date +"%Y%m%d")
    current_time=$(date +"%H%M%S")

    # Use creation date and time if available and requested, otherwise use current date and time
    date_to_use=${creation_date:-$current_date}
    time_to_use=${creation_time:-$current_time}

    # New filename
    new_filename="${project_name}-${project_type}-${project_version}-${date_to_use}-${time_to_use}-${environment}.${final_extension}"

    # Rename the file
    if mv "$file" "$new_filename"; then
      echo "File successfully renamed to: $new_filename"
    else
      echo "Error: Failed to rename '$file'."
    fi
  done
fi
