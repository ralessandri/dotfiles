tmn() { tmux new-session ${1:+-s "$1"}; }

alias tml='tmux list-sessions'

alias tma='tmux a'
alias tmas='tmux attach-session -t'

alias tmks='tmux kill-session -t'
alias tmksa='tmux kill-session -a'