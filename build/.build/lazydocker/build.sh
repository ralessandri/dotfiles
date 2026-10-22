#!/usr/bin/env bash
set -euo pipefail

############################################################
# LazyDocker build script using Docker Compose + Go toolchain
# Version: 1.0
############################################################

# Configuration
SERVICE_NAME="lazydocker-build"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$PROJECT_DIR/compose.yml"
LAZYDOCKER_DIR="$PROJECT_DIR/lazydocker"

# Binary output path
BINARY_LAZYDOCKER="$LAZYDOCKER_DIR/lazydocker"

# Last build commit tracking
LAST_BUILD_FILE="$PROJECT_DIR/.last-build"

############################################################
# Logging Helpers
############################################################

log() {
  printf "\033[1;36m[INFO]\033[0m %s\n" "$*"
}

error() {
  printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2
  exit 1
}

############################################################
# Preconditions
############################################################

if ! command -v docker >/dev/null 2>&1; then
  error "Docker is not installed or not available in PATH."
fi

if ! command -v docker compose >/dev/null 2>&1; then
  error "Docker Compose v2 is required (docker compose)."
fi

if [[ ! -d "$LAZYDOCKER_DIR" ]]; then
  error "The 'lazydocker/' directory does not exist. Expected repository at: $LAZYDOCKER_DIR"
fi

if [[ ! -d "$LAZYDOCKER_DIR/.git" ]]; then
  error "The 'lazydocker/' directory is not a Git repository. Cannot perform git pull."
fi

############################################################
# Parse options
############################################################

CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --clean)
    CLEAN_BUILD=true
    shift
    ;;
  *)
    error "Unknown option: $1"
    ;;
  esac
done

############################################################
# Git Update
############################################################

log "Updating repository in ./lazydocker via git pull…"

(
  cd "$LAZYDOCKER_DIR"
  git fetch --all --prune
  git pull --ff-only || {
    error "Git pull failed. Resolve conflicts manually."
  }
)

log "Repository successfully updated."

############################################################
# Build Necessity Detection (Commit Hash)
############################################################

CURRENT_COMMIT="$(cd "$LAZYDOCKER_DIR" && git rev-parse HEAD)"

if [[ -f "$LAST_BUILD_FILE" ]]; then
  LAST_BUILD_COMMIT="$(cat "$LAST_BUILD_FILE")"
else
  LAST_BUILD_COMMIT=""
fi

if [[ "$CURRENT_COMMIT" == "$LAST_BUILD_COMMIT" && "$CLEAN_BUILD" = false ]]; then
  log "No new commits detected since last build. Skipping build."
  log "Last built commit: $LAST_BUILD_COMMIT"
  exit 0
fi

log "New commit detected or clean build requested."
log "Current commit: $CURRENT_COMMIT"

############################################################
# Optional Clean
############################################################

if [[ "$CLEAN_BUILD" = true ]]; then
  log "Performing clean build…"
  rm -rf "$LAZYDOCKER_DIR/.cache" "$BINARY_LAZYDOCKER"
fi

############################################################
# Build Process
############################################################

log "Starting LazyDocker build using Docker Compose…"

docker compose -f "$COMPOSE_FILE" run --rm "$SERVICE_NAME"

log "Build completed."

############################################################
# Artifact Validation
############################################################

if [[ ! -f "$BINARY_LAZYDOCKER" ]]; then
  error "Build failed: binary 'lazydocker' not found at $BINARY_LAZYDOCKER"
fi

log "Binary 'lazydocker' verified at: $BINARY_LAZYDOCKER"
log "Size: $(du -h "$BINARY_LAZYDOCKER" | cut -f1)"

############################################################
# Installation
############################################################

log "Installing binary into ~/.local/bin …"

install -v -m 755 "$BINARY_LAZYDOCKER" ~/.local/bin/lazydocker

log "Installation completed successfully."

############################################################
# Record last built commit
############################################################

echo "$CURRENT_COMMIT" >"$LAST_BUILD_FILE"
log "Recorded build commit: $CURRENT_COMMIT"
