#!/usr/bin/env bash

set -euo pipefail

# Configuration
readonly CLIP_TIME=45
readonly FLATPAK_APP_ID='com.bitwarden.desktop'

declare -a BW_COMMAND=()
unlocked_by_script=false

# Helpers
show_help() {
  cat <<'EOF'
Usage: rofi-bitwarden.sh

Search Bitwarden login entries with Rofi and copy credentials temporarily.

Keys:
  Enter      Copy the password.
  Alt+Enter  Open actions for the selected entry.

The native bw CLI is preferred. If it is unavailable, the Bitwarden Flatpak
CLI is used instead.
EOF
}

die() {
  printf 'rofi-bitwarden: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

notify() {
  local message="$1"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send 'Bitwarden' "$message"
  else
    printf 'rofi-bitwarden: %s\n' "$message" >&2
  fi
}

_rofi_menu() {
  local prompt="$1"

  shift
  rofi -dmenu -i -p "$prompt" "$@"
}

set_bw_command() {
  local native_bw

  native_bw="$(type -P bw || true)"

  if [[ -n "$native_bw" ]]; then
    BW_COMMAND=("$native_bw")
    if "${BW_COMMAND[@]}" --version >/dev/null 2>&1; then
      return
    fi
  fi

  if command -v flatpak >/dev/null 2>&1; then
    # The Flatpak desktop app bundles the supported bw CLI on this system.
    BW_COMMAND=(flatpak run --command=bw "$FLATPAK_APP_ID")
    if "${BW_COMMAND[@]}" --version >/dev/null 2>&1; then
      return
    fi
  fi

  if [[ -n "$native_bw" ]]; then
    die 'the native bw CLI could not be started and the Flatpak CLI is unavailable'
  else
    die 'neither a usable native bw CLI nor the Bitwarden Flatpak CLI is available'
  fi
}

_bw() {
  "${BW_COMMAND[@]}" "$@"
}

# Clipboard handling
cleanup() {
  if [[ "$unlocked_by_script" == true ]]; then
    _bw lock >/dev/null 2>&1 ||
      printf 'rofi-bitwarden: could not lock the vault\n' >&2
  fi
}

copy_temporary() {
  local value
  local current

  value="$(cat)"
  [[ -n "$value" ]] || return 1

  printf '%s' "$value" | wl-copy --sensitive

  # Keep the guard running after this short-lived selector exits.
  (
    sleep "$CLIP_TIME"
    current="$(wl-paste --no-newline 2>/dev/null || true)"

    if [[ "$current" == "$value" ]]; then
      wl-copy --clear
    fi
  ) >/dev/null 2>&1 &
}

# Vault workflow
unlock_vault() {
  local master_password
  local session
  local message='Unlock your Bitwarden vault.'

  while true; do
    master_password="$(rofi \
      -dmenu \
      -password \
      -p 'Master password' \
      -mesg "$message" \
      -theme-str 'entry { placeholder: "Enter password"; }')" || exit 0

    if [[ -z "$master_password" ]]; then
      message='Enter your master password, or press Esc to cancel.'
      continue
    fi

    BW_PASSWORD="$master_password"
    export BW_PASSWORD
    unset master_password

    if session="$(_bw unlock --raw --passwordenv BW_PASSWORD 2>/dev/null)"; then
      unset BW_PASSWORD

      if [[ -n "$session" ]]; then
        # Bitwarden requires BW_SESSION for subsequent vault commands.
        export BW_SESSION="$session"
        unset session
        unlocked_by_script=true
        return
      fi
    else
      unset BW_PASSWORD
    fi

    message='Password was not accepted. Try again, or press Esc to cancel.'
  done
}

_get_item() {
  local item_id="$1"
  local items_json="$2"

  jq -ce --arg id "$item_id" '
    map(select(.id == $id)) |
    if length == 1 then .[0] else error("selected item could not be resolved") end
  ' <<<"$items_json" 2>/dev/null
}

_get_item_value() {
  local item_json="$1"
  local field="$2"

  jq -r --arg field "$field" '.[$field] // empty' <<<"$item_json"
}

show_entry() {
  local item_json="$1"
  local details

  details="$(jq -r '
    [
      "Name: \(.name)",
      "Username: \(if .username == "" then "(not set)" else .username end)",
      "Email: \(if .email == "" then "(not set)" else .email end)",
      "URLs:",
      (.uris[]? // "(not set)")
    ] | join("\n")
  ' <<<"$item_json")"

  printf '%s\n' "$details" | _rofi_menu 'Bitwarden entry' -no-custom >/dev/null || true
}

copy_field() {
  local item_json="$1"
  local field="$2"
  local value

  value="$(_get_item_value "$item_json" "$field")"

  if [[ -z "$value" ]]; then
    notify "Field '$field' not found"
    return 0
  fi

  printf '%s' "$value" | copy_temporary
}

open_url() {
  local item_json="$1"
  local url

  url="$(jq -r '.uris[0] // empty' <<<"$item_json")"

  if [[ -z "$url" ]]; then
    notify "Field 'url' not found"
    return 0
  fi

  xdg-open "$url" >/dev/null 2>&1 &
  notify 'Opening URL.'
}

edit_entry() {
  local item_id="$1"
  local item_json="$2"
  local field
  local label
  local current
  local value
  local update_filter
  local message

  field="$(printf '%s\n' \
    'Name' \
    'Username' \
    'Email' \
    'URL' |
    _rofi_menu 'Edit Bitwarden field')" || exit 0

  case "$field" in
  Name)
    label='Name'
    current="$(_get_item_value "$item_json" name)"
    update_filter='.name = $value'
    ;;
  Username)
    label='Username'
    current="$(_get_item_value "$item_json" username)"
    update_filter='.login.username = $value'
    ;;
  Email)
    label='Email'
    current="$(_get_item_value "$item_json" email)"
    update_filter='
      .fields |= (
        if any(.[]?; (.name // "" | ascii_downcase) == "email") then
          map(if (.name // "" | ascii_downcase) == "email" then .value = $value else . end)
        else
          . + [{name: "email", value: $value, type: 0}]
        end
      )
    '
    ;;
  URL)
    label='URL'
    current="$(jq -r '.uris[0] // empty' <<<"$item_json")"
    update_filter='
      .login.uris |= (
        if length == 0 then
          [{uri: $value}]
        else
          .[0].uri = $value
        end
      )
    '
    ;;
  '')
    exit 0
    ;;
  *)
    die "unknown edit field: $field"
    ;;
  esac

  message="Update the $label field."

  while true; do
    # -filter pre-fills dmenu's editable input with the existing field value.
    value="$(printf '%s\n' "$current" |
      _rofi_menu "Edit $label" \
        -filter "$current" \
        -mesg "$message" \
        -theme-str 'entry { placeholder: "Enter value"; }')" || exit 0

    if [[ -z "$value" ]]; then
      current=''
      message="$label must not be empty."
      continue
    fi

    # Only URLs have a stable format to validate; other fields are free-form.
    if [[ "$field" == URL && ! "$value" =~ ^[[:alpha:]][[:alnum:]+.-]*://[^[:space:]]+$ ]]; then
      current="$value"
      message='Enter a URL with a scheme, for example https://example.com.'
      continue
    fi

    break
  done

  if ! _bw get item "$item_id" |
    jq --arg value "$value" "$update_filter" |
    _bw encode |
    _bw edit item "$item_id" >/dev/null; then
    die 'selected entry could not be updated'
  fi

  notify "$label updated"
}

# Option parsing
while (($# > 0)); do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
done

# Command dispatch
for command in jq rofi wl-copy wl-paste xdg-open; do
  require_command "$command"
done

set_bw_command
trap cleanup EXIT

status="$(_bw status | jq -er '.status')" || die 'could not determine vault status'

case "$status" in
unlocked) ;;
locked) unlock_vault ;;
unauthenticated)
  die 'log into Bitwarden before using this script'
  ;;
*)
  die "unexpected vault status: $status"
  ;;
esac

items_json="$(_bw list items | jq -ce '
  [
    .[] |
    select(.type == 1) |
    {
      id,
      name: (.name // ""),
      username: (.login.username // ""),
      email: (
        [
          .fields[]? |
          select((.name // "" | ascii_downcase) == "email") |
          .value // empty
        ] | first // ""
      ),
      uris: [.login.uris[]?.uri // empty]
    }
  ]
')" || die 'could not list Bitwarden login entries'

mapfile -t labels < <(jq -r '
  .[] |
  .name as $name |
  .username as $username |
  if $username == "" then $name else "\($name) — \($username)" end |
  gsub("[\\r\\n\\t]"; " ")
' <<<"$items_json")
mapfile -t item_ids < <(jq -r '.[].id' <<<"$items_json")

((${#labels[@]} > 0)) || exit 0

selection_status=0
selection="$(printf '%s\n' "${labels[@]}" |
  _rofi_menu 'Bitwarden' -kb-custom-1 'Alt+Return' -format i)" || selection_status=$?

[[ "$selection_status" -eq 1 ]] && exit 0
[[ "$selection" =~ ^[0-9]+$ ]] || exit 0
((selection < ${#item_ids[@]})) || die 'selected entry could not be resolved'

item_id="${item_ids[selection]}"

if [[ "$selection_status" -eq 0 ]]; then
  _bw get password "$item_id" | copy_temporary ||
    die 'selected entry has no password'
  exit 0
fi

if [[ "$selection_status" -eq 10 ]]; then
  action="$(printf '%s\n' \
    'Copy username' \
    'Copy email' \
    'Open URL' \
    'Show entry' \
    'Edit entry' |
    _rofi_menu 'Bitwarden action')" || exit 0

  item_json="$(_get_item "$item_id" "$items_json")" ||
    die 'selected entry could not be resolved'

  case "$action" in
  'Copy username') copy_field "$item_json" username ;;
  'Copy email') copy_field "$item_json" email ;;
  'Open URL') open_url "$item_json" ;;
  'Show entry') show_entry "$item_json" ;;
  'Edit entry') edit_entry "$item_id" "$item_json" ;;
  '') exit 0 ;;
  *) die "unknown action: $action" ;;
  esac
fi
