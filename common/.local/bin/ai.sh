#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Config
# ----------------------------
MODEL_GEMINI="gemini-3.1-flash-lite"
MODEL_GROQ="llama-3.1-70b-versatile"
MODEL_OPENAI="gpt-4o-mini"

GEMINI_API_KEY=$(secret-tool lookup service gemini)

# ----------------------------
# Argument Parsing
# ----------------------------
SYSTEM_INSTRUCTION=""
USER_PROMPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -s | --system)
    SYSTEM_INSTRUCTION="$2"
    shift 2
    ;;
  *)
    if [[ -z "${USER_PROMPT}" ]]; then
      USER_PROMPT="$1"
    else
      USER_PROMPT="${USER_PROMPT} $1"
    fi
    shift
    ;;
  esac
done

if [[ -z "${USER_PROMPT}" ]]; then
  echo "Usage: ai [-s \"system instruction\"] \"your prompt\""
  exit 1
fi

# ----------------------------
# Helpers
# ----------------------------
fail() {
  echo "[!] $1" >&2
}

# ----------------------------
# Gemini
# ----------------------------
ask_gemini() {
  local payload
  payload="$(
    jq -n \
      --arg sys "${SYSTEM_INSTRUCTION}" \
      --arg user "${USER_PROMPT}" \
      '{
      contents: [{ parts: [{ text: $user }] }]
    } + (if $sys != "" then { system_instruction: { parts: [{ text: $sys }] } } else {} end)'
  )"

  curl -sS --fail-with-body \
    "https://generativelanguage.googleapis.com/v1beta/models/${MODEL_GEMINI}:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}" | jq -r '.candidates[0].content.parts[0].text'
}

# ----------------------------
# Groq
# ----------------------------
ask_groq() {
  local payload
  payload="$(
    jq -n \
      --arg sys "${SYSTEM_INSTRUCTION}" \
      --arg user "${USER_PROMPT}" \
      --arg model "${MODEL_GROQ}" \
      '{
      model: $model,
      messages: (
        (if $sys != "" then [{ role: "system", content: $sys }] else [] end) +
        [{ role: "user", content: $user }]
      )
    }'
  )"

  curl -sS --fail-with-body https://api.groq.com/openai/v1/chat/completions \
    -H "Authorization: Bearer ${GROQ_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}" | jq -r '.choices[0].message.content'
}

# ----------------------------
# OpenAI fallback
# ----------------------------
ask_openai() {
  local payload
  payload="$(
    jq -n \
      --arg sys "${SYSTEM_INSTRUCTION}" \
      --arg user "${USER_PROMPT}" \
      --arg model "${MODEL_OPENAI}" \
      '{
      model: $model,
      messages: (
        (if $sys != "" then [{ role: "system", content: $sys }] else [] end) +
        [{ role: "user", content: $user }]
      )
    }'
  )"

  curl -sS --fail-with-body https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}" | jq -r '.choices[0].message.content'
}

# ----------------------------
# Router (failover logic)
# ----------------------------
run_chain() {
  echo "[→] Gemini..." >&2
  if OUT=$(ask_gemini 2>/dev/null); then
    echo "$OUT"
    return 0
  fi

  fail "Gemini failed → switching to Groq"
  echo "[→] Groq..." >&2
  if OUT=$(ask_groq 2>/dev/null); then
    echo "$OUT"
    return 0
  fi

  fail "Groq failed → switching to OpenAI"
  echo "[→] OpenAI..." >&2
  if OUT=$(ask_openai 2>/dev/null); then
    echo "$OUT"
    return 0
  fi

  fail "All providers failed"
  return 1
}

# ----------------------------
# Run
# ----------------------------
run_chain
