# Search file contents and open a selected match in the editor
fif() {
  local query
  local selection
  local file
  local line

  query="${1:-}"
  if [[ -z "$query" ]]; then
    printf '%s\n' "Usage: fif <search-term>" >&2
    return 2
  fi

  selection=$(rg \
    --line-number \
    --no-heading \
    --smart-case \
    --hidden \
    --glob '!.git' \
    -- "$query" |
    fzf \
      --delimiter ':' \
      --nth '3..' \
      --preview='bat --color=always --style=numbers --highlight-line {2} {1}')

  [[ -z "$selection" ]] && return

  IFS=: read -r file line _ <<<"$selection"
  "${EDITOR:-vim}" "+${line}" "$file"
}

# Find files with the most matches and open a selected file in the editor
fifc() {
  local query selection file

  query="${1:-}"
  if [[ -z "$query" ]]; then
    printf '%s\n' "Usage: fifc <search-term>" >&2
    return 2
  fi

  selection="$(
    rg \
      --count-matches \
      --with-filename \
      --smart-case \
      --hidden \
      --glob '!.git' \
      -- "$query" . |
      LC_ALL=C sort -t: -k2,2nr |
      FIFC_QUERY="$query" fzf \
        --delimiter ':' \
        --nth 1 \
        --preview='rg --color=always --line-number --smart-case -- "$FIFC_QUERY" {1}'
  )" || return

  [[ -z "$selection" ]] && return

  file="${selection%:*}"
  "${EDITOR:-vim}" "$file"
}

# Find a directory and change to it
cdf() {
  local dir

  dir=$(fd . -H --exclude .git --type d |
    fzf --preview='eza -la --tree --level=2 --color=always {}')

  [[ -n "$dir" ]] && cd "$dir"
}

# Find a frequently used directory and change to it
cdz() {
  local dir

  dir=$(zoxide query -l |
    fzf --preview='eza -la --color=always {}')

  [[ -n "$dir" ]] && cd "$dir"
}

# Open a frequently used directory in Neovim
ez() {
  local selection
  local dir

  selection=$(zoxide query -ls |
    fzf --no-sort --preview='eza -la --color=always {2..}')

  [[ -z "$selection" ]] && return

  dir=$(sed -E 's/^[[:space:]]*[^[:space:]]+[[:space:]]+//' <<<"$selection")
  (cd -- "$dir" && nvim .)
}

# Find a file and open it in the editor
ef() {
  local file

  file=$(fd . -H --exclude .git --type f |
    fzf --preview='bat --color=always --style=numbers {}')

  [[ -n "$file" ]] && "${EDITOR:-vim}" "$file"
}

# Choose processes to terminate
kp() {
  local selection
  local -a pids

  selection=$(ps -eo pid=,user=,stat=,args= |
    fzf --multi)

  [[ -z "$selection" ]] && return

  mapfile -t pids < <(awk '{print $1}' <<<"$selection")
  gum confirm "Terminate ${#pids[@]} selected process(es)?" || return

  kill "${pids[@]}"
}
