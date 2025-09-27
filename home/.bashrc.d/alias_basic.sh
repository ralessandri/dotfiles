alias reload='source ~/.bashrc'

alias l='ls -CF'
alias la='ls -A'
alias ll='ls -alF'
alias llh='ls -alFh'
alias ls='ls --color=auto'

alias cat='bat'

alias du="du -h --max-depth=1"

alias ff='f() { fd . -H --exclude .git --type f | fzf --query="$*" --preview "bat --style=numbers --color=always --line-range=:100 {}"; }; f'

alias controller-on='sudo bash -c "echo Y > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM deactivated'
alias controller-off='sudo bash -c "echo N > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM activated'

alias ddev-dump='ddev export-db > $(basename $(pwd))-$(date +%Y%m%d-%H%M%S).sql.gz'

alias open='nautilus $1 2>/dev/null'

alias path='echo -e ${PATH//:/\\n}'