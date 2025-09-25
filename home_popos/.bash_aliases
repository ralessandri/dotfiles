ALIAS_DIR="$HOME/.bashrc.d"

if [ -d "$ALIAS_DIR" ]; then
  for alias_file in "$ALIAS_DIR"/*; do
    [ -r "$alias_file" ] && source "$alias_file"
  done
fi