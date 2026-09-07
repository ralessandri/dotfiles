#!/usr/bin/env bash
# Pick a project directory from zoxide, then focus the matching workspace
# in the configured Herdr session. If the workspace does not exist yet,
# create it first.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly SESSION_NAME="${HERDR_SESSION:-default}"
readonly MATCH_NO_WORKSPACE=1
readonly MATCH_API_ERROR=2
readonly MATCH_EMPTY_PANES=3

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

warn() {
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 214 "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

on_error() {
  local line="$1"
  local cmd="$2"
  local status="$3"

  die "command failed (exit $status) at line $line: $cmd"
}

trap 'on_error "$LINENO" "$BASH_COMMAND" "$?"' ERR

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
}

require_tty() {
  [[ -t 0 && -t 1 ]] || die "this command requires an interactive terminal"
}

_herdr() {
  herdr --session "$SESSION_NAME" "$@"
}

ensure_herdr_ready() {
  _herdr workspace list >/dev/null 2>&1 || die "unable to access Herdr session '$SESSION_NAME'"
}

canonicalize_dir() {
  local dir="$1"

  if [[ -d "$dir" ]]; then
    (cd -- "$dir" && pwd -P)
  else
    printf '%s\n' "$dir"
  fi
}

workspace_label_for_dir() {
  local dir="$1"
  local base parent

  base="$(basename "$dir")"
  parent="$(basename "$(dirname "$dir")")"

  if [[ -n "$parent" && "$parent" != "." && "$parent" != "/" ]]; then
    printf '%s (%s)\n' "$base" "$parent"
  else
    printf '%s\n' "$base"
  fi
}

path_hash() {
  local value="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print substr($1, 1, 8)}'
  else
    printf '%s' "$value" | cksum | awk '{print $1}'
  fi
}

pick_directory() {
  local candidates selected status

  if ! candidates="$(zoxide query -l 2>/dev/null)"; then
    die "zoxide query failed"
  fi

  [[ -n "$candidates" ]] || die "zoxide has no tracked directories yet"

  set +e
  selected="$(
    printf '%s\n' "$candidates" |
      gum filter --placeholder "Select a project directory"
  )"
  status=$?
  set -e

  case "$status" in
  0)
    ;;
  1 | 130)
    exit 0
    ;;
  *)
    die "directory picker failed"
    ;;
  esac

  [[ -n "$selected" ]] || exit 0

  printf '%s\n' "$selected"
}

workspace_list_json() {
  local json

  if ! json="$(_herdr workspace list)"; then
    return "$MATCH_API_ERROR"
  fi

  printf '%s\n' "$json"
}

list_workspace_ids() {
  local json ids

  if json="$(workspace_list_json)"; then
    :
  else
    return "$?"
  fi

  if ! ids="$(
    jq -r '
      (.workspaces // .result.workspaces // .result.snapshot.workspaces // [])
      | .[]
      | (.workspace_id // .id // empty)
    ' <<<"$json"
  )"; then
    return "$MATCH_API_ERROR"
  fi

  printf '%s\n' "$ids"
  return 0
}

list_workspace_labels() {
  local json labels

  if json="$(workspace_list_json)"; then
    :
  else
    return "$?"
  fi

  if ! labels="$(
    jq -r '
      (.workspaces // .result.workspaces // .result.snapshot.workspaces // [])
      | .[]
      | (.label // empty)
    ' <<<"$json"
  )"; then
    return "$MATCH_API_ERROR"
  fi

  printf '%s\n' "$labels"
  return 0
}

workspace_root_cwd() {
  local workspace_id="$1"
  local pane_json root_cwd

  if ! pane_json="$(_herdr pane list --workspace "$workspace_id")"; then
    return "$MATCH_API_ERROR"
  fi

  # Herdr returns panes in creation/order-of-arrival order; the first pane is
  # the workspace anchor and is the stable root we want to match against.
  if ! root_cwd="$(
    jq -r '
      (.result.panes // .panes // [])
      | if length == 0 then empty else .[0].cwd // empty end
    ' <<<"$pane_json"
  )"; then
    return "$MATCH_API_ERROR"
  fi

  if [[ -z "$root_cwd" ]]; then
    return "$MATCH_EMPTY_PANES"
  fi

  printf '%s\n' "$root_cwd"
}

workspace_matches_dir() {
  local workspace_id="$1"
  local dir="$2"
  local selected_cwd root_cwd

  selected_cwd="$(canonicalize_dir "$dir")"

  if root_cwd="$(workspace_root_cwd "$workspace_id")"; then
    :
  else
    return "$?"
  fi

  root_cwd="$(canonicalize_dir "$root_cwd")"

  [[ "$root_cwd" == "$selected_cwd" || "$root_cwd" == "$dir" ]]
}

workspace_id_for_dir() {
  local dir="$1"
  local workspace_ids workspace_id
  local saw_empty_panes=false
  local status

  if workspace_ids="$(list_workspace_ids)"; then
    :
  else
    status=$?
    case "$status" in
    "$MATCH_API_ERROR")
      return "$MATCH_API_ERROR"
      ;;
    *)
      return "$MATCH_NO_WORKSPACE"
      ;;
    esac
  fi

  [[ -n "$workspace_ids" ]] || return "$MATCH_NO_WORKSPACE"

  while IFS= read -r workspace_id; do
    [[ -n "$workspace_id" ]] || continue
    if workspace_matches_dir "$workspace_id" "$dir"; then
      printf '%s\n' "$workspace_id"
      return 0
    else
      status=$?
      case "$status" in
      "$MATCH_NO_WORKSPACE")
        ;;
      "$MATCH_EMPTY_PANES")
        saw_empty_panes=true
        warn "workspace '$workspace_id' has no panes; skipping cwd match"
        ;;
      "$MATCH_API_ERROR")
        return "$MATCH_API_ERROR"
        ;;
      *)
        return "$MATCH_API_ERROR"
        ;;
      esac
    fi
  done <<<"$workspace_ids"

  if [[ "$saw_empty_panes" == true ]]; then
    return "$MATCH_EMPTY_PANES"
  fi

  return "$MATCH_NO_WORKSPACE"
}

unique_workspace_label_for_dir() {
  local dir="$1"
  local labels base_label candidate hash suffix

  base_label="$(workspace_label_for_dir "$dir")"

  if labels="$(list_workspace_labels)"; then
    :
  else
    return "$?"
  fi

  if ! grep -Fxq -- "$base_label" <<<"$labels"; then
    printf '%s\n' "$base_label"
    return 0
  fi

  hash="$(path_hash "$dir")"
  candidate="${base_label} [${hash}]"

  if ! grep -Fxq -- "$candidate" <<<"$labels"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  suffix=2
  while grep -Fxq -- "${candidate} #${suffix}" <<<"$labels"; do
    suffix=$((suffix + 1))
  done

  printf '%s\n' "${candidate} #${suffix}"
}

focus_or_create_workspace() {
  local dir="$1"
  local label workspace_id status

  ensure_herdr_ready

  if workspace_id="$(workspace_id_for_dir "$dir")"; then
    _herdr workspace focus "$workspace_id" >/dev/null
    return 0
  else
    status=$?
    case "$status" in
    "$MATCH_NO_WORKSPACE")
      ;;
    "$MATCH_EMPTY_PANES")
      warn "at least one candidate workspace has no panes; creating a new workspace"
      ;;
    "$MATCH_API_ERROR")
      die "failed while resolving existing workspaces for '$dir'"
      ;;
    *)
      die "unexpected workspace lookup failure for '$dir'"
      ;;
    esac
  fi

  if [[ ! -d "$dir" ]]; then
    die "selected directory no longer exists: $dir"
  fi

  if label="$(unique_workspace_label_for_dir "$dir")"; then
    :
  else
    status=$?
    if [[ "$status" -eq "$MATCH_API_ERROR" ]]; then
      die "failed while resolving a unique workspace label"
    fi
    die "failed while preparing workspace label"
  fi

  _herdr workspace create \
    --cwd "$dir" \
    --label "$label" \
    --focus >/dev/null
}

main() {
  require_cmd herdr
  require_cmd jq
  require_cmd gum
  require_cmd zoxide
  require_tty

  local dir
  dir="$(pick_directory)"
  focus_or_create_workspace "$dir"
}

main "$@"
