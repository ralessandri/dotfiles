#!/usr/bin/env bash
# update-starship-palette.sh
# Ensures "palette = \"matugen\"" is at the top and replaces the [palettes.matugen] section.

set -euo pipefail

STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
PALETTE_FILE="${1:-$HOME/.config/starship/starship-matugen-palette.toml}"

if [[ ! -f "$STARSHIP_CONFIG" ]]; then
  echo "Error: starship.toml not found at $STARSHIP_CONFIG" >&2
  exit 1
fi

if [[ ! -f "$PALETTE_FILE" ]]; then
  echo "Error: palette file not found at $PALETTE_FILE" >&2
  exit 1
fi

tmp_file=$(mktemp)

# 1. Remove any existing top-level "palette = ..." line
# 2. Remove the entire [palettes.matugen] section
awk '
    BEGIN { in_palette = 0 }

    # Skip old top-level palette line
    /^palette[[:space:]]*=/ { next }

    # Detect start of [palettes.matugen]
    /^\[palettes\.matugen\]/ { in_palette = 1; next }

    # End of palette section when a new section starts
    /^\[/ && in_palette { in_palette = 0 }

    # Print everything that is not inside the palette section
    !in_palette { print }
' "$STARSHIP_CONFIG" >"$tmp_file"

# Build the final file:
# - Put "palette = \"matugen\"" at the very top
# - Then the rest of the config
# - Then the new [palettes.matugen] block

{
  echo 'palette = "matugen"'
  echo ""
  cat "$tmp_file"
  echo ""
  cat "$PALETTE_FILE"
} >"${tmp_file}.final"

mv "${tmp_file}.final" "$STARSHIP_CONFIG"
rm -f "$tmp_file"

echo "Starship palette updated successfully"
