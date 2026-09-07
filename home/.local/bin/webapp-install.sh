#!/usr/bin/env bash
set -euo pipefail

readonly ICON_DIR="$HOME/.local/share/applications/icons"
readonly DESKTOP_DIR="$HOME/.local/share/applications"
readonly FLATPAK_APP_ID="org.chromium.Chromium"
readonly FLATPAK_CONFIG_DIR="$HOME/.var/app/${FLATPAK_APP_ID}/config/chromium"
readonly NO_PROFILE_LABEL="None (default / last used)"

readonly COLOR_GREEN='\e[32m'
readonly COLOR_YELLOW='\e[33m'
readonly COLOR_RESET='\e[0m'

APP_NAME=""
APP_URL=""
ICON_REF=""
CUSTOM_EXEC=""
MIME_TYPES=""
PROFILE=""
INTERACTIVE_MODE=false

usage() {
  cat <<'EOF'
Usage:
  webapp-install.sh
  webapp-install.sh --name NAME --url URL [--icon ICON] [--exec CMD] [--mime-types TYPES] [--profile PROFILE]

Options:
  -n, --name NAME         Web app name. Required in non-interactive mode.
  -u, --url URL           Web app URL. Required in non-interactive mode.
  -i, --icon ICON         Icon reference. Omit to download a favicon automatically.
                          Use a URL to download a PNG or a filename inside ~/.local/share/applications/icons.
  -e, --exec CMD          Custom Exec command for the launcher.
  -m, --mime-types TYPES  Optional MimeType list, separated by semicolons.
  -p, --profile PROFILE   Chromium profile directory to use.
  -h, --help              Show this help text.

Examples:
  webapp-install.sh --name Claude --url https://claude.ai
  webapp-install.sh --name Discord --url https://discord.com/channels/@me --icon discord.png
EOF
}

# Abort with an error message on stderr.
die() {
  echo "Error: $*" >&2
  exit 1
}

# Verify that all required commands are available.
check_dependencies() {
  local missing=()
  local cmd
  for cmd in curl flatpak; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ $INTERACTIVE_MODE == true ]]; then
    command -v gum >/dev/null 2>&1 || missing+=("gum")
  fi
  if ((${#missing[@]} > 0)); then
    die "missing required command(s): ${missing[*]}"
  fi
}

# List installed Chromium profile directory names (e.g. "Default", "Profile 1").
# A directory counts as a profile if it contains a "Preferences" file.
find_chromium_profiles() {
  local profiles=()
  local dir

  [[ -d $FLATPAK_CONFIG_DIR ]] || return 0

  for dir in "$FLATPAK_CONFIG_DIR"/*/; do
    [[ -f "${dir}Preferences" ]] || continue
    profiles+=("$(basename "$dir")")
  done

  ((${#profiles[@]} > 0)) || return 0
  printf '%s\n' "${profiles[@]}" | sort -u
}

# Prefix a URL with https:// if no scheme was given.
normalize_url() {
  local url=$1
  if [[ ! $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
    url="https://$url"
  fi
  printf '%s' "$url"
}

# Google's favicon service, used as a fallback icon source.
favicon_url_for() {
  printf 'https://www.google.com/s2/favicons?domain=%s&sz=128' "$1"
}

# Extract the hostname from a URL for favicon downloads.
favicon_domain_for() {
  local url=$1

  if [[ $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$url"
  fi
}

# Download an icon from a URL into the target path.
# Returns non-zero if the download failed or produced an empty file.
download_icon() {
  local url=$1
  local target=$2
  curl -fsSL -o "$target" "$url" && [[ -s $target ]]
}

# Prompt the user for all required values via gum.
prompt_for_app_details() {
  echo -e "${COLOR_GREEN}Let's create a new web app you can start with the app launcher.\n${COLOR_RESET}"

  APP_NAME=$(gum input --prompt "Name> " --placeholder "My favorite web app")
  APP_URL=$(gum input --prompt "URL> " --placeholder "https://example.com")
  APP_URL=$(normalize_url "$APP_URL")

  mkdir -p "$ICON_DIR"
  local icon_path="$ICON_DIR/$APP_NAME.png"
  if download_icon "$(favicon_url_for "$(favicon_domain_for "$APP_URL")")" "$icon_path"; then
    ICON_REF="$APP_NAME.png"
  else
    ICON_REF=$(gum input \
      --prompt "Icon URL> " \
      --placeholder "Could not fetch favicon automatically. Enter PNG icon URL (see https://dashboardicons.com)")
  fi

  PROFILE=$(prompt_for_profile)
  CUSTOM_EXEC=""
  MIME_TYPES=""
}

# Ask the user to pick a Chromium profile, if any are available.
prompt_for_profile() {
  local -a available_profiles
  mapfile -t available_profiles < <(find_chromium_profiles)

  if ((${#available_profiles[@]} > 0)); then
    local choice
    choice=$(gum choose \
      --header "Select Chromium profile" \
      "$NO_PROFILE_LABEL" \
      "${available_profiles[@]}")
    [[ $choice == "$NO_PROFILE_LABEL" ]] && choice=""
    printf '%s' "$choice"
  else
    echo -e "${COLOR_YELLOW}No Chromium profiles found under $FLATPAK_CONFIG_DIR. You can enter a profile name manually.${COLOR_RESET}" >&2
    gum input --prompt "Chromium Profile> " --placeholder "Leave empty for default (e.g. Default, Profile 1)"
  fi
}

# Parse named command-line arguments for non-interactive use.
parse_named_args() {
  while (($#)); do
    case $1 in
    -n | --name)
      [[ $# -ge 2 ]] || die "missing value for $1"
      APP_NAME=$2
      shift 2
      ;;
    -u | --url)
      [[ $# -ge 2 ]] || die "missing value for $1"
      APP_URL=$(normalize_url "$2")
      shift 2
      ;;
    -i | --icon)
      [[ $# -ge 2 ]] || die "missing value for $1"
      ICON_REF=$2
      shift 2
      ;;
    -e | --exec)
      [[ $# -ge 2 ]] || die "missing value for $1"
      CUSTOM_EXEC=$2
      shift 2
      ;;
    -m | --mime-types)
      [[ $# -ge 2 ]] || die "missing value for $1"
      MIME_TYPES=$2
      shift 2
      ;;
    -p | --profile)
      [[ $# -ge 2 ]] || die "missing value for $1"
      PROFILE=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
    esac
  done
}

# Resolve ICON_REF (a URL or a filename already inside ICON_DIR) into a
# concrete PNG path on disk, downloading it if necessary.
resolve_icon_path() {
  mkdir -p "$ICON_DIR"

  local reference=$ICON_REF
  [[ -n $reference ]] || reference=$(favicon_url_for "$(favicon_domain_for "$APP_URL")")

  if [[ $reference =~ ^https?:// ]]; then
    local target="$ICON_DIR/$APP_NAME.png"
    download_icon "$reference" "$target" || die "failed to download icon from $reference"
    printf '%s' "$target"
  else
    printf '%s' "$ICON_DIR/$reference"
  fi
}

# Escape a value for safe use inside a double-quoted Exec= argument, per the
# Desktop Entry Specification (backslash, backtick, dollar sign, and double
# quote must be escaped).
desktop_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\$/\\\$}
  value=${value//\`/\\\`}
  printf '"%s"' "$value"
}

# Build the Exec= command line: either a user-supplied custom command, or a
# default invocation of Flatpak Chromium in app mode. Appends the profile
# argument in both cases, when a profile was selected.
build_exec_command() {
  local exec_command

  if [[ -n $CUSTOM_EXEC ]]; then
    exec_command="$CUSTOM_EXEC"
  else
    exec_command="flatpak run $FLATPAK_APP_ID $(desktop_quote "--app=$APP_URL")"
  fi

  if [[ -n $PROFILE ]]; then
    exec_command+=" $(desktop_quote "--profile-directory=$PROFILE")"
  fi

  printf '%s' "$exec_command"
}

# Write the .desktop launcher file.
write_desktop_file() {
  local exec_command=$1
  local icon_path=$2
  local desktop_file="$DESKTOP_DIR/$APP_NAME.desktop"

  mkdir -p "$DESKTOP_DIR"
  cat >"$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=$APP_NAME
Exec=$exec_command
Terminal=false
Type=Application
Icon=$icon_path
StartupNotify=true
EOF

  if [[ -n $MIME_TYPES ]]; then
    echo "MimeType=$MIME_TYPES" >>"$desktop_file"
  fi

  chmod +x "$desktop_file"
  printf '%s' "$desktop_file"
}

print_summary() {
  local desktop_file=$1
  echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
  if [[ -n $PROFILE ]]; then
    echo -e "Using Chromium profile: ${COLOR_YELLOW}$PROFILE${COLOR_RESET}\n"
  fi
}

main() {
  if (($# == 0)); then
    INTERACTIVE_MODE=true
  else
    INTERACTIVE_MODE=false
    parse_named_args "$@"
  fi

  check_dependencies

  if [[ $INTERACTIVE_MODE == true ]]; then
    prompt_for_app_details
  fi

  [[ -n ${APP_NAME:-} && -n ${APP_URL:-} ]] || {
    usage
    die "name and url are required in non-interactive mode"
  }
  [[ $APP_NAME != */* ]] || die "app name must not contain slashes"

  local icon_path
  icon_path=$(resolve_icon_path)

  local exec_command
  exec_command=$(build_exec_command)

  local desktop_file
  desktop_file=$(write_desktop_file "$exec_command" "$icon_path")

  if [[ $INTERACTIVE_MODE == true ]]; then
    print_summary "$desktop_file"
  fi
}

main "$@"
