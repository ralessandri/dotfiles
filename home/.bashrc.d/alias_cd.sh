alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

alias cdf='cd "$(fd . -H --exclude .git --type d | fzf --preview "tree -aC {}")"'
alias cdh='dir=$(zoxide query -ls | fzf | awk "{print \$2}") && [ -n "$dir" ] && cd "$dir"'