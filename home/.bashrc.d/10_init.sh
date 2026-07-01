###############################################################################
# Environment Initialization
#
# Initializes third-party tools and environment variables.
###############################################################################

###############################################################################
# Homebrew
###############################################################################

# Initialize Homebrew environment if installed
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

###############################################################################
# Node Version Manager (NVM)
###############################################################################

# Set NVM environment variables
export NVM_DIR="${HOME}/.nvm"
export NVM_HOMEBREW="/home/linuxbrew/.linuxbrew/opt/nvm"

# Load NVM if available
if [[ -s "${NVM_HOMEBREW}/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  . "${NVM_HOMEBREW}/nvm.sh"
fi

###############################################################################
# Zoxide
###############################################################################

# Initialize zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
