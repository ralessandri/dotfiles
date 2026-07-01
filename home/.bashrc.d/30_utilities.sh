###############################################################################
# Utilities
###############################################################################

# Display command-line cheat sheets from cheat.sh
cheat() {
  curl "https://cheat.sh/${1}"
}

# Display the weather forecast from wttr.in
wttr() {
  curl "https://wttr.in/${1}"
}

###############################################################################
# File Management
###############################################################################

# Open a directory in Nautilus
#
# Usage:
#   open
#   open ~/Downloads
open() {
  nautilus "${1:-.}" >/dev/null 2>&1 &
}

###############################################################################
# Search
###############################################################################

# Search for files using fd and preview them with bat
#
# Usage:
#   ff
#   ff nginx
#   ff Dockerfile
fif() {
  fd . -H --exclude .git --type f |
    fzf \
      --query="$*" \
      --preview='bat --style=numbers --color=always --line-range=:100 {}'
}

###############################################################################
# Navigation
###############################################################################

# Change to a directory selected with fd and fzf
cdf() {
  local dir

  dir=$(fd . -H --exclude .git --type d |
    fzf --preview='tree -aC {}')

  [[ -n "$dir" ]] && cd "$dir"
}

# Change to a frequently used directory selected with zoxide and fzf
cdh() {
  local dir

  dir=$(zoxide query -ls |
    fzf |
    awk '{print $2}')

  [[ -n "$dir" ]] && cd "$dir"
}
