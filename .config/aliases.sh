# Easier navigation
alias ..="cd .."
alias ...="cd ../.."

# Most of my `find` commands start with `find . -iname`
# Use `fd`
alias fin="find . -name"
alias fiin="find . -iname"

# show path line by line
alias path='echo -e ${PATH//:/\\n}'

# Let tmux support colors
alias tmux="tmux -2"

# Easy attach/ls
alias tmuxa="tmux attach-session\; choose-tree"
alias tmuxj="tmux new-session -A -s journal -n notepad ~/.local/bin/journal"
alias tmuxls="tmux list-sessions"

# colored ls'ing
alias ls='ls -G'

# Check out https://www.atlassian.com/git/tutorials/dotfiles for an in-depth
# explanation. Splitting where you save the git data (which is normally in a
# `.git` folder) and where you save the actual data is convenient in this case.
alias dotfiles='git --git-dir=$HOME/dotfiles/ --work-tree=$HOME'
alias df='dotfiles'

############################# Universal double CDs #############################
function cdesk() {
  double_cd "$HOME/Desktop" $1
}

function cdev() {
  double_cd "$HOME/dev" $1
}

