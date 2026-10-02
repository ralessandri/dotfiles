#!/usr/bin/env bash

set -uo pipefail

SELF="$(readlink -f "$0")"

# Images may contain sensitive clipboard data.
# Therefore, keep decoded thumbnails in the runtime directory
# instead of ~/.cache.
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/dms-rofi-clipboard-${UID}"

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# Launcher
#
# When this script is started directly, launch Rofi.
# When Rofi invokes the script, ROFI_RETV is already set.
# ─────────────────────────────────────────────────────────────

if [[ ! -v ROFI_RETV ]]; then
  exec rofi \
    -show dmsclip \
    -modes "dmsclip:${SELF}" \
    -show-icons \
    -kb-custom-1 "Alt+Return"
fi

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

mime_ext() {
  case "$1" in
  image/png) printf 'png' ;;
  image/jpeg) printf 'jpg' ;;
  image/webp) printf 'webp' ;;
  image/gif) printf 'gif' ;;
  image/bmp) printf 'bmp' ;;
  image/svg+xml) printf 'svg' ;;
  image/tiff) printf 'tiff' ;;
  *) printf 'img' ;;
  esac
}

# ─────────────────────────────────────────────────────────────
# Image thumbnail handling
# ─────────────────────────────────────────────────────────────

image_for_id() {
  local id="$1"
  local mime="$2"

  local ext
  local file
  local json
  local data tmp

  ext="$(mime_ext "$mime")"
  file="${CACHE_DIR}/${id}.${ext}"

  # Return the cached image if it has already been decoded.
  if [[ -s "$file" ]]; then
    printf '%s' "$file"
    return 0
  fi

  json="$(dms cl get "$id" --json 2>/dev/null)" || return 1

  data="$(
    jq -r '.data // empty' <<<"$json"
  )"

  [[ -n "$data" ]] || return 1

  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if ! printf '%s' "$data" | base64 -d >"$tmp" 2>/dev/null; then
    rm -f -- "$tmp"
    return 1
  fi

  if ! mv -f -- "$tmp" "$file"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod 600 "$file" 2>/dev/null || true

  printf '%s' "$file"
}

# ─────────────────────────────────────────────────────────────
# Rofi mode header
# ─────────────────────────────────────────────────────────────

header() {
  printf '\0prompt\x1fClipboard\n'

  printf '\0message\x1fEnter: copy   Alt+Enter: copy + paste\n'

  printf '\0no-custom\x1ftrue\n'
  printf '\0use-hot-keys\x1ftrue\n'
}

# ─────────────────────────────────────────────────────────────
# Generate clipboard entries
# ─────────────────────────────────────────────────────────────

list_entries() {
  local history
  local entries

  history="$(
    dms cl history --json 2>/dev/null
  )" || {
    printf '\0message\x1fUnable to reach the DMS clipboard server\n'
    return
  }

  entries="$(jq -r '
          (if type == "array" then . else [.] end)
          | to_entries
          | map(.value + {"__order": .key})
          | sort_by([
              if .pinned == true then 0 else 1 end,
              .__order
            ])
          | .[]
          | [
              (.id | tostring),
              (.isImage | tostring),
              (.mimeType // "application/octet-stream"),
              ((.preview // "") | gsub("[\\t\\r\\n]+"; " "))
            ]
          | @tsv
        ' <<<"$history")" || {
    printf '\0message\x1fInvalid clipboard history data\n'
    return
  }

  local id
  local is_image
  local mime
  local preview

  local icon
  local image_path

  while IFS=$'\t' read -r \
    id \
    is_image \
    mime \
    preview; do
    [[ -n "$id" ]] || continue

    [[ -n "$preview" ]] || preview="(no preview)"

    # Avoid displaying excessively long clipboard contents in Rofi.
    if ((${#preview} > 180)); then
      preview="${preview:0:177}…"
    fi

    # ── Icon or image thumbnail

    if [[ "$is_image" == "true" ]]; then

      image_path="$(
        image_for_id "$id" "$mime" 2>/dev/null ||
          true
      )"

      if [[ -n "$image_path" ]]; then
        icon="thumbnail://${image_path}"
      else
        icon="image-x-generic"
      fi

    else
      icon="edit-copy"
    fi

    # The visible text is only used for display and searching.
    # The stable DMS entry ID is stored invisibly in the "info" field.
    #
    # This allows multiple clipboard entries to contain identical text
    # without losing the association with the correct DMS entry.

    printf '%s' "$preview"
    printf '\0display\x1f%s' "$preview"
    printf '\0info\x1f%s' "$id"
    printf '\0icon\x1f%s' "$icon"
    printf '\n'

  done <<<"$entries"
}

# ─────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────

id="${ROFI_INFO:-}"

case "${ROFI_RETV:-0}" in

# Initial invocation
0)
  header
  list_entries
  ;;

# Enter
#
# Let DMS restore the clipboard entry itself so MIME types
# and binary data are handled correctly.
1)
  if [[ -n "$id" ]]; then
    dms cl get "$id" --copy >/dev/null 2>&1
  fi
  ;;

# Custom action 1
# Alt+Enter
#
# Restore the selected entry to the clipboard and then send
# a paste keystroke to the previously focused application.
10)
  if [[ -n "$id" ]] &&
    dms cl get "$id" --copy >/dev/null 2>&1; then
    # Give Rofi a moment to close before sending the paste command.
    (
      sleep 0.18
      dms cl send-paste >/dev/null 2>&1
    ) &
  fi
  ;;

*)
  header
  list_entries
  ;;

esac
