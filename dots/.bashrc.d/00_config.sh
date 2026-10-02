export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if ! declare -p STASH_DOTFILES_DIR &>/dev/null; then
  STASH_DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
fi
readonly STASH_DOTFILES_DIR
export STASH_DOTFILES_DIR

if ! declare -p STASH_ROOT_DIR &>/dev/null; then
  STASH_ROOT_DIR="$(dirname "$STASH_DOTFILES_DIR")"
fi
readonly STASH_ROOT_DIR
export STASH_ROOT_DIR

# Bash history
export HISTCONTROL=ignorespace:erasedups

# Tool configuration
export EDITOR=nvim
# export DOCKER_CONFIG="${XDG_CONFIG_HOME}/docker"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export WEZTERM_CONFIG_FILE="$XDG_CONFIG_HOME/wezterm/wezterm.lua"
export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'

# PATH
case ":$PATH:" in
*":$HOME/.cargo/bin:"*) ;;
*) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
