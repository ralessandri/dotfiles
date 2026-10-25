#!/usr/bin/env bash
set -euo pipefail

# Configuration
target="$HOME/.local/bin/bw"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/bw-update.XXXXXX")"
staged_path="$(mktemp "${target}.new.XXXXXX")"
trap 'rm -rf -- "$work_dir"; rm -f -- "$staged_path"' EXIT

# Helpers
_fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Update workflow
command -v gum >/dev/null 2>&1 || _fail 'gum is required.'
command -v curl >/dev/null 2>&1 || _fail 'curl is required.'
command -v python3 >/dev/null 2>&1 || _fail 'python3 is required.'
command -v unzip >/dev/null 2>&1 || _fail 'unzip is required.'
command -v sha256sum >/dev/null 2>&1 || _fail 'sha256sum is required.'
command -v bw >/dev/null 2>&1 || _fail 'Bitwarden CLI (bw) is not installed.'
[[ -x "$target" ]] || _fail "Expected executable not found: ${target}"
[[ "$(command -v bw)" == "$target" ]] || _fail "The active bw command is not ${target}."
current_version="$(bw -v 2>&1 | tr -d '\r')"

output_path="${work_dir}/update-output"
if ! gum spin --spinner dot --title 'Checking for Bitwarden CLI updates…' -- sh -c "bw update >\"\$1\" 2>&1" _ "$output_path"; then
  cat "$output_path" >&2
  _fail 'Bitwarden update check failed.'
fi

download_url="$(grep -Eo 'https://github\.com/bitwarden/clients/releases/download/cli-v[^[:space:]]+/bw-linux-[^[:space:]]+\.zip' "$output_path" | tail -n 1 || true)"
if [[ -z "$download_url" ]]; then
  printf '%s\n' 'No downloadable update was reported by bw update:'
  sed -n '1,8p' "$output_path"
  exit 0
fi

if [[ ! "$download_url" =~ ^https://github\.com/bitwarden/clients/releases/download/cli-v[0-9]+\.[0-9]+\.[0-9]+/bw-linux-[0-9]+\.[0-9]+\.[0-9]+\.zip$ ]]; then
  _fail 'The update check returned an unexpected download URL.'
fi

expected_version="${download_url##*/bw-linux-}"
expected_version="${expected_version%.zip}"
printf 'Downloading Bitwarden CLI %s.\n' "$expected_version"
release_path="${work_dir}/release.json"
gum spin --spinner dot --title 'Retrieving the release SHA-256…' -- curl --fail --location --silent --show-error --header 'Accept: application/vnd.github+json' --output "$release_path" "https://api.github.com/repos/bitwarden/clients/releases/tags/cli-v${expected_version}" || _fail 'Could not retrieve release checksum metadata.'
asset_digest="$(python3 -c 'import json, sys
release = json.load(open(sys.argv[1], encoding="utf-8"))
for asset in release.get("assets", []):
    if asset.get("name") == sys.argv[2]:
        print(asset.get("digest") or "")
        raise SystemExit(0)
raise SystemExit("Release asset not found.")' "$release_path" "bw-linux-${expected_version}.zip")" || _fail 'Could not find the release asset digest.'
if [[ ! "$asset_digest" =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
  _fail 'The release metadata does not provide a valid SHA-256 digest.'
fi
expected_hash="${asset_digest#sha256:}"
archive_path="${work_dir}/bw.zip"
gum spin --spinner dot --title "Downloading Bitwarden CLI ${expected_version}…" -- curl --fail --location --silent --show-error --output "$archive_path" "$download_url" || _fail 'Download failed.'
printf '%s  %s\n' "$expected_hash" "$archive_path" | sha256sum --check --status || _fail 'SHA-256 verification failed.'
printf 'Verified SHA-256 for Bitwarden CLI %s.\n' "$expected_version"

candidate_path="${work_dir}/bw"
unzip -p "$archive_path" bw > "$candidate_path" || _fail 'Could not extract the bw executable from the archive.'
chmod 0755 "$candidate_path"
candidate_version="$("$candidate_path" -v 2>&1 | tr -d '\r')"
[[ "$candidate_version" == "$expected_version" ]] || _fail "Downloaded version mismatch: expected ${expected_version}, got ${candidate_version}."

install -m 0755 -- "$candidate_path" "$staged_path"
mv -fT -- "$staged_path" "$target"
printf 'Updated Bitwarden CLI: %s → %s\n' "$current_version" "$expected_version"
