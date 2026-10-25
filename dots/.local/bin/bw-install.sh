#!/usr/bin/env bash
set -euo pipefail

# Configuration
target="$HOME/.local/bin/bw"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/bw-install.XXXXXX")"
staged_path=''
trap 'rm -rf -- "$work_dir"; [[ -z "$staged_path" ]] || rm -f -- "$staged_path"' EXIT

# Helpers
_fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Install workflow
command -v gum >/dev/null 2>&1 || _fail 'gum is required.'
command -v curl >/dev/null 2>&1 || _fail 'curl is required.'
command -v python3 >/dev/null 2>&1 || _fail 'python3 is required.'
command -v unzip >/dev/null 2>&1 || _fail 'unzip is required.'
command -v sha256sum >/dev/null 2>&1 || _fail 'sha256sum is required.'
[[ "$(uname -m)" == x86_64 ]] || _fail 'The native Bitwarden CLI archive is available here for x86_64 only.'
mkdir -p -- "${target%/*}"
staged_path="$(mktemp "${target}.new.XXXXXX")"

releases_path="${work_dir}/releases.json"
gum spin --spinner dot --title 'Finding the latest Bitwarden CLI release…' -- curl --fail --location --silent --show-error --header 'Accept: application/vnd.github+json' --output "$releases_path" 'https://api.github.com/repos/bitwarden/clients/releases?per_page=100' || _fail 'Could not retrieve Bitwarden releases.'
asset_metadata="$(python3 -c 'import json, sys
for release in json.load(open(sys.argv[1], encoding="utf-8")):
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not tag.startswith("cli-v"):
        continue
    version = tag.removeprefix("cli-v")
    expected = f"bw-linux-{version}.zip"
    for asset in release.get("assets", []):
        if asset.get("name") == expected:
            print(asset["browser_download_url"], asset.get("digest") or "", sep="\t")
            raise SystemExit(0)
raise SystemExit("No stable Linux CLI archive found.")' "$releases_path")" || _fail 'Could not find the latest stable Linux CLI archive.'
IFS=$'\t' read -r download_url asset_digest <<< "$asset_metadata"

if [[ ! "$download_url" =~ ^https://github\.com/bitwarden/clients/releases/download/cli-v[0-9]+\.[0-9]+\.[0-9]+/bw-linux-[0-9]+\.[0-9]+\.[0-9]+\.zip$ ]]; then
  _fail 'The release list returned an unexpected download URL.'
fi

expected_version="${download_url##*/bw-linux-}"
expected_version="${expected_version%.zip}"
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
printf 'Installed Bitwarden CLI %s at %s.\n' "$expected_version" "$target"
