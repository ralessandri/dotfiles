#!/usr/bin/env bash

# General-purpose rsync with archive mode and overall progress
alias rs='rsync -ah --info=progress2 --stats'

# Compressed network transfer; keep partial files if interrupted
alias rsz='rsync -ahz --partial --info=progress2 --stats'

# Readable dry run; show files that would be transferred
alias rsd='rsync -avhn --stats'

# Detailed diagnostic dry run
alias rsdi='rsync -avhn --itemize-changes'

# Mirror dry run; inspect transfers and deletions before running rsm
alias rsmd='rsync -avhn --delete --stats'

# Mirror source to destination, including deletions
alias rsm='rsync -avh --delete --partial --info=progress2 --stats'

# Additive Linux home backup using a central exclude file
alias rsb='rsync -aAXh --partial --info=progress2 --stats --exclude-from="$HOME/.config/rsync/excludes"'

# Filtered mirror dry run; excluded files remain protected at destination
alias rsbmd='rsync -aAXvhn --delete --stats --exclude-from="$HOME/.config/rsync/excludes"'

# Filtered mirror; destination follows source while excluded files remain untouched
alias rsbm='rsync -aAXvh --delete --partial --info=progress2 --stats --exclude-from="$HOME/.config/rsync/excludes"'

# Expensive content-based integrity check instead of size/mtime quick-check
alias rsc='rsync -acvhn --stats'
