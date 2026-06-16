#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Load colors from ~/.env if available, else use defaults
if [[ -f ~/.env ]]; then
  source ~/.env
fi

PASTEL_BLUE=${PASTEL_BLUE:-"\033[1;34m"}
PASTEL_YELLOW=${PASTEL_YELLOW:-"\033[1;33m"}
PASTEL_GREEN=${PASTEL_GREEN:-"\033[1;32m"}
PASTEL_PINK=${PASTEL_PINK:-"\033[1;35m"}
NC=${NC:-"\033[0m"}

print_header() {
  printf "${PASTEL_BLUE}\n"
  echo "=========================================="
  echo -e "🚀 $1"
  echo "=========================================="
  printf "${NC}\n"
}

print_section() {
  printf "${PASTEL_YELLOW}--------------------\n"
  echo -e "$1"
  echo "--------------------"
  printf "${NC}\n"
}

success_message() {
  printf "${PASTEL_GREEN}✅ %s${NC}\n" "$1"
}

info_message() {
  printf "${PASTEL_BLUE}ℹ️  %s${NC}\n" "$1"
}

error_message() {
  printf "${PASTEL_PINK}❌ %s${NC}\n" "$1"
}

run_and_report() {
  local cmd="$1"
  local ok="$2"
  local fail="$3"

  if eval "$cmd"; then
    success_message "$ok"
  else
    error_message "$fail"
  fi
}

available() {
  command -v "$1" &>/dev/null
}
