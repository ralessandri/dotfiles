#!/usr/bin/env bash

###############################################################################
# Development
###############################################################################

# Export the current DDEV database with a timestamp
alias ddev-dump='ddev export-db > $(basename $(pwd))-$(date +%Y%m%d-%H%M%S).sql.gz'

# Open Neovim
alias n='nvim'

###############################################################################
# Local Commands
###############################################################################

# Run setup Just recipes
alias must='just --justfile "$STASH_ROOT_DIR/setup/justfile"'

# Run global Just recipes
alias gust='just -g'

# Bitwarden
#alias bw='flatpak run --command=bw com.bitwarden.desktop'

###############################################################################
# Custom Scripts
###############################################################################

# Basic ai connector
alias ai="ai.sh"

# Browse documented Bash aliases and functions
alias bash-help='bash-help.sh'

# Generate an AI-assisted Git commit message
alias ai-commit='ai-commit.sh'

# Launch dmenu
alias dmenu='dmenu.sh'

# Run backup script
alias dobackup='dobackup.sh'

# Start PhpStorm
alias phpstorm='phpstorm.sh'

# Rename dump files
alias renadump='renamdump.sh'

# Launch Toolbox helper
alias tbx='tbx.sh'

# Run the system update script
alias update='update.sh'
