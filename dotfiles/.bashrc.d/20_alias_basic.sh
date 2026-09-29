###############################################################################
# Shell
###############################################################################

# Reload the current Bash configuration
alias reload='source ~/.bashrc'

# Clear the terminal screen
alias c='clear'

# Exit the current shell
alias q='exit'

###############################################################################
# Navigation
###############################################################################

# Change to the parent directory
alias ..='cd ..'

# Change to the grandparent directory
alias ...='cd ../..'

# Change three levels up
alias ....='cd ../../..'

###############################################################################
# File Management
###############################################################################

# Use bat as a replacement for cat
alias cat='bat'

# Restow managed dotfiles
alias restow='(cd -- "$HOME/.stash" && stow -R --no-folding dotfiles)'

# Show directory sizes (current level only)
alias du='du -h --max-depth=1'

# Short directory listing
alias l='eza --classify=always'

# List all entries in a single column with directories first
alias l1='eza -1a --group-directories-first'

# List all files except . and ..
alias la='ls -A'

# Detailed directory listing
alias ll='eza -al --icons --group-directories-first'

# Display a two-level directory tree with icons
alias lt='eza -al --tree -L 2 --icons=auto'

# Detailed directory listing with human-readable file sizes
alias llh='eza -al --binary --classify=always'

# Enable colored output for ls
alias ls='eza'

# Display PATH entries line by line
alias path='echo -e ${PATH//:/\\n}'
