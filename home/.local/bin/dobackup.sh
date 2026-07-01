#!/usr/bin/env bash
# Description: Simple rsync-based backup script with subcommands and options.
# Author: Your Name
# License: MIT

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="1.0.1"

# === Helper Functions ======================================================

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [OPTIONS] <subcommand>

Subcommands:
  run               Run the backup (default)
  dry-run           Simulate backup without changing anything
  verify            Verify backup using checksums

Options:
  -h, --help        Show this help message and exit
  -v, --version     Show version and exit
  -s, --source DIR  Source directory (required)
  -t, --target DIR  Target directory (required)
  -d, --delete      Mirror mode: delete files not present in source
  -z, --compress    Enable compression (useful for remote targets)

Notes:
  - .git directories are automatically excluded from the backup.

Examples:
  $SCRIPT_NAME --source ~/Documents --target /mnt/backup run
  $SCRIPT_NAME -s /data -t user@server:/backup -z dry-run
EOF
}

version() {
  echo "$SCRIPT_NAME version $VERSION"
}

log() {
  # Log helper function
  # Arguments:
  #   $1: message
  echo "[INFO] $1"
}

error() {
  # Error helper function
  # Arguments:
  #   $1: error message
  echo "[ERROR] $1" >&2
  exit 1
}

# === Main Logic ===========================================================

main() {
  local source=""
  local target=""
  local delete_flag=false
  local compress_flag=false
  local subcommand="run"

  # Parse long options manually
  for arg in "$@"; do
    case $arg in
    --help)
      usage
      exit 0
      ;;
    --version)
      version
      exit 0
      ;;
    --delete)
      delete_flag=true
      ;;
    --compress)
      compress_flag=true
      ;;
    --source)
      shift
      source="${1:-}"
      ;;
    --target)
      shift
      target="${1:-}"
      ;;
    esac
  done

  # Parse short options
  while getopts ":hvs:t:dz" opt; do
    case ${opt} in
    h)
      usage
      exit 0
      ;;
    v)
      version
      exit 0
      ;;
    s)
      source="$OPTARG"
      ;;
    t)
      target="$OPTARG"
      ;;
    d)
      delete_flag=true
      ;;
    z)
      compress_flag=true
      ;;
    \?)
      error "Invalid option: -$OPTARG"
      ;;
    :)
      error "Option -$OPTARG requires a value."
      ;;
    esac
  done
  shift $((OPTIND - 1))

  # Detect subcommand
  if [[ $# -gt 0 ]]; then
    subcommand="$1"
    shift
  fi

  # Validate required arguments
  [[ -z "$source" ]] && error "Source directory is required (use -s)"
  [[ -z "$target" ]] && error "Target directory is required (use -t)"

  # Build rsync options
  local rsync_opts=(-avh --progress --exclude='.git/')
  [[ "$delete_flag" == true ]] && rsync_opts+=("--delete")
  [[ "$compress_flag" == true ]] && rsync_opts+=("-z")

  # Execute subcommand
  case "$subcommand" in
  run)
    log "Running backup from '$source' to '$target'"
    rsync "${rsync_opts[@]}" "$source" "$target"
    ;;
  dry-run)
    log "Simulating backup (dry-run) from '$source' to '$target'"
    rsync --dry-run "${rsync_opts[@]}" "$source" "$target"
    ;;
  verify)
    log "Verifying backup integrity using checksums"
    rsync --checksum --dry-run "${rsync_opts[@]}" "$source" "$target"
    ;;
  *)
    error "Unknown subcommand: $subcommand"
    ;;
  esac
}

main "$@"
