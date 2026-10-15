#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# Found updates: package manager -> list of pending updates
declare -A UPDATES=()
declare -A COUNTS=()
# Order of package managers with pending updates
PENDING=()
# Show progress messages during the check phase
VERBOSE=false
# Run the restart check with needs-restarting
REBOOT_CHECK=false
# Temporary files and running background process (for cleanup)
TMP_FILES=()
CHECK_PID=""

# Colors (only in a terminal and when NO_COLOR is not set)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly C_RESET=$'\e[0m' C_BOLD=$'\e[1m'
  readonly C_BLUE=$'\e[34m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RED=$'\e[31m'
else
  readonly C_RESET="" C_BOLD="" C_BLUE="" C_GREEN="" C_YELLOW="" C_RED=""
fi

# Output helpers

_header() { printf '\n%s:: %s%s\n\n' "${C_BLUE}${C_BOLD}" "$1" "$C_RESET"; }
_info() { printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$1"; }
_ok() { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
_warn() { printf '%s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
_err() { printf '%s✖%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
_indent() { sed 's/^/  /'; }

# Helpers

_has_command() {
  command -v "$1" >/dev/null 2>&1
}

_cleanup() {
  [[ -n "$CHECK_PID" ]] && kill "$CHECK_PID" 2>/dev/null || true
  ((${#TMP_FILES[@]} > 0)) && rm -f "${TMP_FILES[@]}" || true
}
trap _cleanup EXIT
trap 'exit 130' INT TERM

# Use the spinner only when gum is available, output is a terminal, and
# verbose mode is off (otherwise the spinner and progress output would overlap)
_use_spinner() {
  [[ "$VERBOSE" == false && -t 1 ]] && _has_command gum
}

# Over SSH, the polkit agent is unavailable, so Flatpak needs sudo
_is_remote_session() {
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]] && return 0
  [[ -n "${XDG_SESSION_ID:-}" ]] && _has_command loginctl || return 1
  [[ "$(loginctl show-session "$XDG_SESSION_ID" -p Remote --value 2>/dev/null)" == "yes" ]]
}

_flatpak_priv() {
  if _is_remote_session; then
    sudo flatpak "$@"
  else
    flatpak "$@"
  fi
}

_show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Check for updates on every supported package manager, show the pending
updates, and (after confirmation) upgrade and clean up.

Options:
  -c, --check         Only list pending updates, do not install anything.
  -y, --yes           Do not ask for confirmation before upgrading.
  -r, --reboot-check  Report whether a reboot or service restarts are needed
                      (uses needs-restarting).
  -v, --verbose       Show progress messages of the package managers while
                      checking for updates. Disables the spinner.
  -h, --help          Show this help message and exit.

Supported package managers:
  apt, dnf, flatpak, brew, cargo (requires cargo-update)

Notes:
  - Only package managers available on the current system are used.
  - Commands that require elevated privileges may prompt for sudo access.
  - If gum is installed, a spinner is shown while checking for updates.
  - The output of the upgrade phase is always shown in full.
  - Set NO_COLOR to disable colored output.
EOF
}

# Run a step and report its result consistently
_run_step() {
  local label="$1"
  shift

  if "$@"; then
    _ok "${label} completed."
  else
    _err "${label} failed."
    return 1
  fi
}

# Phase 1: check (prints pending updates to stdout and installs nothing)
# Progress messages go to stderr.

_check_apt() {
  local -a quiet=(-qq)
  [[ "$VERBOSE" == true ]] && quiet=()

  sudo apt update "${quiet[@]}" >&2
  apt list --upgradable 2>/dev/null | tail -n +2
}

_check_dnf() {
  local out rc=0
  local -a quiet=(-q)
  [[ "$VERBOSE" == true ]] && quiet=()

  # Exit code: 0 = no updates, 100 = updates available, otherwise an error
  out="$(dnf check-upgrade --refresh "${quiet[@]}")" || rc=$?
  case "$rc" in
  0) ;;
  100) printf '%s\n' "$out" ;;
  *) return "$rc" ;;
  esac
}

_check_flatpak() {
  flatpak remote-ls --updates --columns=application,version,origin
}

_check_brew() {
  brew update >&2
  brew outdated
}

_check_cargo() {
  local out grep_rc

  # Lines with "Yes" in the "Needs update" column
  out="$(cargo install-update -l)" || return $?
  if grep -E 'Yes[[:space:]]*$' <<<"$out"; then
    return 0
  else
    grep_rc=$?
    [[ "$grep_rc" -eq 1 ]]
  fi
}

_collect() {
  local name="$1" check_fn="$2"
  local outfile errfile rc=0 out count

  outfile="$(mktemp)"
  errfile="$(mktemp)"
  TMP_FILES+=("$outfile" "$errfile")

  # Start the check in the background so the spinner can run alongside it.
  # In verbose mode, leave stderr (progress output) visible in the terminal.
  if [[ "$VERBOSE" == true ]]; then
    "$check_fn" >"$outfile" &
  else
    "$check_fn" >"$outfile" 2>"$errfile" &
  fi
  CHECK_PID=$!

  if _use_spinner; then
    # Keep this script single-quoted so the inner Bash expands $1 with the PID.
    gum spin --spinner minidot --title "Checking ${name} ..." -- \
      bash -c 'while kill -0 "$1" 2>/dev/null; do sleep 0.1; done' _ "$CHECK_PID"
  else
    _info "Checking ${name} ..."
  fi

  wait "$CHECK_PID" || rc=$?
  CHECK_PID=""

  if ((rc != 0)); then
    _err "${name}: check failed."
    [[ -s "$errfile" ]] && _indent <"$errfile" >&2
    return 1
  fi

  out="$(<"$outfile")"
  if [[ -n "$out" ]]; then
    count="$(printf '%s\n' "$out" | grep -c .)"
    UPDATES["$name"]="$out"
    COUNTS["$name"]="$count"
    PENDING+=("$name")
    _ok "${name}: ${count} update(s) available."
  else
    _ok "${name}: up to date."
  fi
}

_show_pending() {
  local name

  _header "Pending updates"
  for name in "${PENDING[@]}"; do
    printf '%s%s (%s)%s\n' "$C_BOLD" "$name" "${COUNTS[$name]}" "$C_RESET"
    printf '%s\n' "${UPDATES[$name]}" | _indent
  done
}

# Phase 2: upgrade + cleanup (only for package managers with updates)

_update_apt() {
  _header "Upgrading apt"
  _run_step "apt upgrade" sudo apt upgrade -y
  _run_step "apt autoremove" sudo apt autoremove -y
}

_update_dnf() {
  _header "Upgrading dnf"
  _run_step "dnf upgrade" sudo dnf upgrade --refresh -y
  _run_step "dnf autoremove" sudo dnf autoremove -y
}

_update_flatpak() {
  _header "Upgrading flatpak"
  _run_step "flatpak update" _flatpak_priv update -y
  _run_step "flatpak cleanup" _flatpak_priv uninstall --unused
}

_update_brew() {
  _header "Upgrading brew"
  _run_step "brew upgrade" brew upgrade
  _run_step "brew cleanup" brew cleanup --prune=all
  _run_step "brew autoremove" brew autoremove
}

_update_cargo() {
  _header "Upgrading cargo"
  _run_step "cargo update" cargo install-update -a
}

# Restart check

_report_restart_needs() {
  _header "Restart check"

  if ! _has_command needs-restarting; then
    _warn "needs-restarting is not installed, skipping reboot check."
    return 0
  fi

  local reboot_out services rc=0

  # -r: exit code 1 when a reboot is recommended
  reboot_out="$(needs-restarting -r 2>&1)" || rc=$?
  case "$rc" in
  0) _ok "No reboot required." ;;
  1)
    _warn "Reboot required."
    printf '%s\n' "$reboot_out" | _indent >&2
    ;;
  *) _err "Could not determine reboot status (exit code ${rc})." ;;
  esac

  # -s: services that should be restarted after the update
  services="$(needs-restarting -s 2>/dev/null || true)"
  if [[ -n "$services" ]]; then
    _warn "Services to restart:"
    printf '%s\n' "$services" | _indent >&2
  fi
}

# Run the check only when the option is set
_maybe_report_restart_needs() {
  if [[ "$REBOOT_CHECK" == true ]]; then
    _report_restart_needs
  fi
  return 0
}

# CLI

main() {
  local check_only=false assume_yes=false found=false check_failed=false answer name

  while (($# > 0)); do
    case "$1" in
    -h | --help)
      _show_help
      return 0
      ;;
    -c | --check) check_only=true ;;
    -y | --yes) assume_yes=true ;;
    -r | --reboot-check) REBOOT_CHECK=true ;;
    -v | --verbose) VERBOSE=true ;;
    *)
      _err "Unknown option: $1"
      printf 'Try %s --help for usage information.\n' "$SCRIPT_NAME" >&2
      return 1
      ;;
    esac
    shift
  done

  # Request the sudo password in advance so the prompt does not
  # conflict with the spinner (apt update requires sudo)
  if _has_command apt; then
    sudo -v
  fi

  # Phase 1: find updates
  _header "Checking for updates"
  _has_command apt && {
    if ! _collect apt _check_apt; then
      check_failed=true
    fi
    found=true
  }
  _has_command dnf && {
    if ! _collect dnf _check_dnf; then
      check_failed=true
    fi
    found=true
  }
  _has_command flatpak && {
    if ! _collect flatpak _check_flatpak; then
      check_failed=true
    fi
    found=true
  }
  _has_command brew && {
    if ! _collect brew _check_brew; then
      check_failed=true
    fi
    found=true
  }
  _has_command cargo-install-update && {
    if ! _collect cargo _check_cargo; then
      check_failed=true
    fi
    found=true
  }

  if [[ "$found" == false ]]; then
    _err "No supported package manager found."
    return 1
  fi

  if [[ "$check_failed" == true ]]; then
    _err "One or more update checks failed; no upgrades will be run."
    return 1
  fi

  if ((${#PENDING[@]} == 0)); then
    printf '\n'
    _ok "Everything is up to date."
    _maybe_report_restart_needs
    return 0
  fi

  # Display results
  _show_pending
  if [[ "$check_only" == true ]]; then
    _maybe_report_restart_needs
    return 0
  fi

  # Confirmation
  if [[ "$assume_yes" == false ]]; then
    printf '\n%s::%s Proceed with upgrade? [y/N] ' "${C_BLUE}${C_BOLD}" "$C_RESET"
    read -r answer || answer=n
    if [[ ! "$answer" =~ ^[yYjJ]$ ]]; then
      _info "Aborted."
      return 0
    fi
  fi

  # Phase 2: upgrade
  for name in "${PENDING[@]}"; do
    "_update_${name}"
  done

  printf '\n'
  _ok "All upgrades completed."
  _maybe_report_restart_needs
}

main "$@"
