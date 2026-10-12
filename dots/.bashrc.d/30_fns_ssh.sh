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
