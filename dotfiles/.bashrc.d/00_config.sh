STASH_DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
readonly STASH_DOTFILES_DIR
export STASH_DOTFILES_DIR

STASH_ROOT_DIR="$(dirname "$STASH_DOTFILES_DIR")"
readonly STASH_ROOT_DIR
export STASH_ROOT_DIR

export HISTCONTROL=ignorespace:erasedups

export EDITOR=nvim
export WEZTERM_CONFIG_FILE="$HOME/.config/wezterm/wezterm.lua"
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"

case ":$PATH:" in
*":$HOME/.cargo/bin:"*) ;;
*) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
