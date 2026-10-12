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

# Change to a Git worktree selected with fzf
gwt() {
  local worktree

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "gwt: not inside a Git worktree" >&2
    return 1
  fi

  worktree=$(git worktree list --porcelain |
    sed -n 's/^worktree //p' |
    fzf --preview='git -C {} status --short --branch')

  [[ -n "$worktree" ]] && cd -- "$worktree"
}
