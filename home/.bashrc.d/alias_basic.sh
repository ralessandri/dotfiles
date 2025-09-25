alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias l='ls -CF'
alias la='ls -A'
alias ll='ls -alF'
alias llh='ls -alFh'
alias ls='ls --color=auto'

alias cat='bat'

alias reload='source ~/.bashrc'

alias du="du -h --max-depth=1"

alias ff='f() { fd . --type f | fzf --query="$*" --preview "bat --style=numbers --color=always --line-range=:100 {}"; }; f'
alias cdf='cd "$(fd . --type d | fzf --preview "tree -C {} | head -n 20")"'
alias cdh='dir=$(zoxide query -ls | fzf | awk "{print \$2}") && [ -n "$dir" ] && cd "$dir"'


alias controller-on='sudo bash -c "echo Y > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM deactivated'
alias controller-off='sudo bash -c "echo N > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM activated'

alias ddev-dump='ddev export-db > $(basename $(pwd))-$(date +%Y%m%d-%H%M%S).sql.gz'