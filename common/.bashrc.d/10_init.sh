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

###############################################################################
# FZF
###############################################################################
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
  --highlight-line \
  --info=inline-right \
  --ansi \
  --border=none \
  --color=bg+:#2e3c64 \
  --color=bg:#1f2335 \
  --color=border:#29a4bd \
  --color=fg:#c0caf5 \
  --color=gutter:#1f2335 \
  --color=header:#ff9e64 \
  --color=hl+:#2ac3de \
  --color=hl:#2ac3de \
  --color=info:#545c7e \
  --color=marker:#ff007c \
  --color=pointer:#ff007c \
  --color=prompt:#2ac3de \
  --color=query:#c0caf5:regular \
  --color=scrollbar:#29a4bd \
  --color=separator:#ff9e64 \
  --color=spinner:#ff007c \
"
