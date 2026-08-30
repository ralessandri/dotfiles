#!/usr/bin/env bash
#
# ai-commit.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly TMP_MSG_FILE="$(mktemp -t ai-commit-msg.XXXXXX)"
readonly GLOBAL_RULES_FILE="${HOME}/.config/ai-commit/.commitrules"
readonly PROJECT_RULES_FILENAME=".commitrules"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
  rm -f "${TMP_MSG_FILE}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
die() {
  gum style --foreground 196 "Error: $*" >&2
  exit 1
}

info() {
  gum style --foreground 245 "$*"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
check_dependencies() {
  local dep
  for dep in git gum ai.sh; do
    command -v "${dep}" >/dev/null 2>&1 ||
      die "Required command '${dep}' not found in PATH."
  done
}

check_git_repository() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "Not inside a git repository."
}

check_staged_changes() {
  if git diff --staged --quiet; then
    die "No staged changes found. Stage your changes with 'git add' first."
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
EXTRA_MESSAGE=""
MESSAGE_FLAG_SET=false
TARGET_PROJECT_DIR=""

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-m "additional context"] [-p "project path"] [-h]

Options:
  -m MESSAGE   Provide additional context for the AI prompt directly.
               Skips the interactive prompt entirely.
  -p PATH      Target git project directory (useful for external calls).
  -h           Show this help message
EOF
}

parse_args() {
  while getopts ":m:p:h" opt; do
    case "${opt}" in
    m)
      EXTRA_MESSAGE="${OPTARG}"
      MESSAGE_FLAG_SET=true
      ;;
    p)
      TARGET_PROJECT_DIR="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    \?) die "Invalid option: -${OPTARG}" ;;
    :) die "Option -${OPTARG} requires an argument." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

# Return success only when a rules file contains at least one non-whitespace
# character. Empty files and files containing only whitespace use the defaults.
has_rules_content() {
  [[ -f "$1" ]] && grep -q '[^[:space:]]' "$1"
}

# Interactively ask for additional context if -m was not provided.
prompt_for_extra_context() {
  if [[ "${MESSAGE_FLAG_SET}" == true ]]; then
    return
  fi

  if gum confirm "Add additional context for the AI?"; then
    EXTRA_MESSAGE="$(gum write --placeholder "Describe additional context (optional)...")"
  fi
}

# Retrieve system instructions using cascading project-level, global, or fallback rules.
get_system_instruction() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  local project_rules="${repo_root}/${PROJECT_RULES_FILENAME}"

  if [[ -n "${repo_root}" ]] && has_rules_content "${project_rules}"; then
    cat "${project_rules}"
    return
  fi

  if has_rules_content "${GLOBAL_RULES_FILE}"; then
    cat "${GLOBAL_RULES_FILE}"
    return
  fi

  cat <<'RULES_EOF'
Generate a git commit message for the following staged diff, strictly
following the Conventional Commits specification.

Rules:
- Format: "<type>(<optional scope>): <subject>"
- Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci,
  chore, revert. Pick the single most fitting type for the overall change.
- Scope is optional; add it only if it clearly improves clarity (e.g. a
  module, component, or package name). Omit it if the change is broad.
- Subject: imperative mood ("add", not "added"/"adds"), lowercase (unless a
  proper noun/identifier requires otherwise), no trailing period, max 50
  characters.
- Leave one blank line after the subject line if a body follows.
- Body (optional, only if it adds real value beyond the subject): explain
  what changed and why, not how. Wrap lines at 72 characters. Use bullet
  points ("- ") for multiple distinct changes.
- Footer (optional): use "BREAKING CHANGE: <description>" if the diff
  introduces a breaking change. Reference issues with "Refs: #123" or
  "Closes: #123" only if such a reference is explicitly given in the
  additional context below - never invent issue numbers.
- Do not fabricate details that are not evident from the diff or the
  additional context.
- Respond with the raw commit message only - no explanations, no markdown
  code fences, no surrounding quotes.
RULES_EOF
}

# Build user prompt containing optional context and staged diff.
build_user_prompt() {
  local diff="$1"
  local prompt=""

  if [[ -n "${EXTRA_MESSAGE}" ]]; then
    prompt+="Additional context from the developer: ${EXTRA_MESSAGE}"$'\n\n'
  fi

  prompt+="Diff:"$'\n'"${diff}"

  printf '%s' "${prompt}"
}

# Send system instruction and user prompt to the ai wrapper script.
generate_ai_message() {
  local system_instruction="$1"
  local user_prompt="$2"
  local message

  message="$(gum spin --spinner dot --title "Generating commit message via AI..." \
    --show-output -- ai.sh -c --system "${system_instruction}" "${user_prompt}")" ||
    die "AI command failed to generate a commit message."

  if [[ -z "${message//[[:space:]]/}" ]]; then
    die "AI returned an empty commit message."
  fi

  printf '%s' "${message}"
}

# Write generated message and reference diff into temporary commit edit file.
build_commit_template() {
  local ai_message="$1"
  local diff="$2"

  {
    printf '%s\n' "${ai_message}"
    printf '\n'
    printf '# To abort this commit: clear this message and save, or exit the editor\n'
    printf '# with a non-zero status (e.g. in vi: ":cq").\n'
    printf '#\n'
    printf '# Staged diff sent to the AI (for reference only, not committed):\n'
    printf '#\n'
    printf '%s\n' "${diff}" | sed 's/^/# /'
  } >"${TMP_MSG_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  if [[ -n "${TARGET_PROJECT_DIR}" ]]; then
    cd "${TARGET_PROJECT_DIR}"
  fi

  check_dependencies
  check_git_repository
  check_staged_changes

  gum style --border normal --margin "1 0" --padding "0 2" --border-foreground 212 \
    "AI Commit Message Generator"

  local diff
  diff="$(git diff --staged)"

  prompt_for_extra_context

  local system_instruction
  system_instruction="$(get_system_instruction)"

  local user_prompt
  user_prompt="$(build_user_prompt "${diff}")"

  local ai_message
  ai_message="$(generate_ai_message "${system_instruction}" "${user_prompt}")"

  build_commit_template "${ai_message}" "${diff}"

  git commit --edit --file="${TMP_MSG_FILE}"
}

main "$@"
