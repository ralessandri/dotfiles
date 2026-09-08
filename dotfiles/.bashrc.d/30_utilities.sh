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
    fzf --preview='eza -la --tree --level=2 --color=always {}')

  [[ -n "$dir" ]] && cd "$dir"
}

# Change to a frequently used directory selected with zoxide and fzf
cdh() {
  local dir

  dir=$(zoxide query -l |
    fzf --preview='eza -la --color=always {}')

  [[ -n "$dir" ]] && cd "$dir"
}

# Open a frequently used directory selected with zoxide and fzf in LazyVim
zvim() {
  local selection
  local dir

  selection=$(zoxide query -ls |
    fzf --no-sort --preview='eza -la --color=always {2..}')

  [[ -z "$selection" ]] && return

  dir=$(sed -E 's/^[[:space:]]*[^[:space:]]+[[:space:]]+//' <<<"$selection")
  (cd -- "$dir" && nvim .)
}

# Open a file selected with fd and fzf
fe() {
  local file

  file=$(fd . -H --exclude .git --type f |
    fzf --preview='bat --color=always --style=numbers {}')

  [[ -n "$file" ]] && "${EDITOR:-vim}" "$file"
}

# Switch local Git branch selected with fzf
gb() {
  local branch
  local local_branch

  branch=$(git branch --all --format='%(refname:short)' |
    grep -v 'origin/HEAD' |
    fzf --preview='git log --oneline --decorate --color=always {} -20')

  [[ -z "$branch" ]] && return

  if [[ "$branch" == origin/* ]]; then
    local_branch="${branch#origin/}"

    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      git switch "$local_branch"
    else
      git switch --track "$branch"
    fi
  else
    git switch "$branch"
  fi
}

# Show a Git commit selected with fzf
glog() {
  local commit

  commit=$(git log \
    --color=always \
    --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' |
    fzf \
      --ansi \
      --no-sort \
      --preview='git show --color=always {1}' |
    awk '{print $1}')

  [[ -n "$commit" ]] && git show "$commit"
}

# Select and kill a process with fzf
fkill() {
  local pid
  dnf repoquery --userinstalled
  pid=$(ps -ef |
    sed 1d |
    fzf -m |
    awk '{print $2}')

  [[ -n "$pid" ]] && kill "$pid"
}

# Select an environment variable with fzf
fenv() {
  env |
    sort |
    fzf
}

# Starts an SSH agent if none is reachable.
ssh-up() {
  local key="${1:-$HOME/.ssh/id_ed25519}"

  if [ ! -f "$key" ]; then
    echo "ssh-up: key not found: $key" >&2
    return 1
  fi

  # ssh-add -l exit codes: 0 = agent up with keys, 1 = agent up but empty,
  # 2 = no agent reachable at all -> need to start one
  ssh-add -l >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  # Only add the key if it isn't already loaded
  local fingerprint
  fingerprint=$(ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}')

  if ssh-add -l 2>/dev/null | grep -q "$fingerprint"; then
    echo "Key already loaded: $key"
  else
    ssh-add -q "$key"
  fi
}

# Terminates the SSH agent running for the current shell session, if any.
ssh-down() {
  [ -n "$SSH_AGENT_PID" ] && eval "$(ssh-agent -k)"
}
