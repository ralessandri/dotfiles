#!/usr/bin/env bash
#
# ai-commit.sh
#
# Generates a git commit message using an AI provider and opens it in the
# configured git editor (vi by default) for review before committing.
#
# The staged diff that was sent to the AI is appended below the generated
# message as a git comment block, so it is visible for reference but is
# automatically stripped by git and NOT part of the final commit message.
#
# Requirements:
#   - git
#   - gum   (https://github.com/charmbracelet/gum)
#   - ai    (existing wrapper script: `ai "prompt"` -> prints AI response)
#
# Usage:
#   ai-commit.sh              Interactive mode, asks whether to add extra context
#   ai-commit.sh -m "text"    Non-interactive, adds "text" as extra context
#   ai-commit.sh -h           Show help
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly TMP_MSG_FILE="$(mktemp -t ai-commit-msg.XXXXXX)"

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
  for dep in git gum ai; do
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
# Tracks whether -m was passed explicitly at all (even as an empty string),
# as opposed to not being passed. This lets callers opt out of the
# interactive prompt on purpose (e.g. in CI / non-interactive shells) by
# passing -m "", while an omitted -m still triggers the interactive dialog.
MESSAGE_FLAG_SET=false

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-m "additional context"] [-h]

Options:
  -m MESSAGE   Provide additional context for the AI prompt directly.
               Skips the interactive prompt entirely - even when MESSAGE
               is an empty string ("") - which is useful for
               non-interactive/CI usage.
  -h           Show this help message

If -m is omitted, you will be asked interactively whether you want to add
extra context for the AI.

The commit message is generated from 'git diff --staged' via the 'ai'
command, opened in the configured git editor for review, and the diff
is appended as a comment block for reference (it is stripped automatically
and will not be part of the final commit).
EOF
}

parse_args() {
  while getopts ":m:h" opt; do
    case "${opt}" in
    m)
      EXTRA_MESSAGE="${OPTARG}"
      MESSAGE_FLAG_SET=true
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

# Interactively ask the user whether they want to add extra context for the
# AI prompt, unless -m was passed explicitly (with or without a value).
prompt_for_extra_context() {
  if [[ "${MESSAGE_FLAG_SET}" == true ]]; then
    return
  fi

  if gum confirm "Add additional context for the AI?"; then
    EXTRA_MESSAGE="$(gum write --placeholder "Describe additional context (optional)...")"
  fi
}

# Build the prompt that is sent to the 'ai' command. Enforces the
# Conventional Commits specification (https://www.conventionalcommits.org/).
build_ai_prompt() {
  local diff="$1"
  local prompt

  prompt="$(
    cat <<'PROMPT_EOF'
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
PROMPT_EOF
  )"

  if [[ -n "${EXTRA_MESSAGE}" ]]; then
    prompt+=$'\n\n'"Additional context from the developer: ${EXTRA_MESSAGE}"
  fi

  prompt+=$'\n\n'"Diff:"$'\n'"${diff}"

  printf '%s' "${prompt}"
}

# Call the AI command with a spinner and return its output.
generate_ai_message() {
  local prompt="$1"
  local message

  message="$(gum spin --spinner dot --title "Generating commit message via AI..." \
    --show-output -- ai "${prompt}")" ||
    die "AI command failed to generate a commit message."

  if [[ -z "${message//[[:space:]]/}" ]]; then
    die "AI returned an empty commit message."
  fi

  printf '%s' "${message}"
}

# Write the AI message plus the diff (as a comment block) to the temp file
# that will be opened in the editor.
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

  check_dependencies
  check_git_repository
  check_staged_changes

  gum style --border normal --margin "1 0" --padding "0 2" --border-foreground 212 \
    "AI Commit Message Generator"

  local diff
  diff="$(git diff --staged)"

  prompt_for_extra_context

  local prompt
  prompt="$(build_ai_prompt "${diff}")"

  local ai_message
  ai_message="$(generate_ai_message "${prompt}")"

  build_commit_template "${ai_message}" "${diff}"

  # Open the template in the configured git editor (vi by default).
  # Comment lines (starting with '#') are stripped automatically by git
  # (default cleanup mode "strip"), so the diff never ends up in the
  # actual commit message.
  git commit --edit --file="${TMP_MSG_FILE}"
}

main "$@"
