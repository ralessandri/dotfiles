# Switch to a local or remote Git branch
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

# Show a selected Git commit
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

# Apply a selected Git stash and remove it on success
gstash() {
  local stash

  stash=$(git stash list --format='%gd%x09%gs' |
    fzf \
      --delimiter=$'\t' \
      --with-nth='2..' \
      --preview='git stash show --color=always --patch {1}')

  [[ -z "$stash" ]] && return

  git stash pop "${stash%%$'\t'*}"
}

# Apply a selected Git stash without removing it
gsstash() {
  local stash

  stash=$(git stash list --format='%gd%x09%gs' |
    fzf \
      --delimiter=$'\t' \
      --with-nth='2..' \
      --preview='git stash show --color=always --patch {1}')

  [[ -z "$stash" ]] && return

  git stash apply "${stash%%$'\t'*}"
}

# Show changes introduced by a branch since it diverged from the current branch
gdiff() {
  local current_branch
  local branch

  current_branch=$(git branch --show-current)
  branch=$(git branch --all --format='%(refname:short)' |
    awk -v current_branch="$current_branch" '$0 != "origin/HEAD" && $0 != current_branch' |
    fzf --preview='git diff --color=always HEAD...{}')

  [[ -n "$branch" ]] && git diff --color=always "HEAD...$branch"
}

# Change to a Git worktree
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
