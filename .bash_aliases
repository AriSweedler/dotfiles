# Easier navigation
alias ..="cd .."
alias ...="cd ../.."
alias cdot="cd ~/dotfiles"
alias cnot="cd ~/Desktop/notes"

function double_cd() {
  if [ -z "$2" ]; then
    cd $1
  else
    cd "$1"/"$2"* || cd "$1"; ls
  fi
}

function cdesk() {
  double_cd "$HOME/Desktop" $1
}

function cdev() {
  double_cd "$HOME/dev" $1
}

# I don't wanna put this in my bin because it's specific to my mac, I guess...
alias debounce='/Users/ari/Desktop/life/housekeeping/debounce-mac/debounce'

# Invoke remote scripts with 'bashcurl'
function bashcurl() {
  bash <(curl --silent $1)
}

# read vim help pages straight from terminal. Allow exiting with 'c'
function vimhelp() {
  vim -c "help $1" -c "only" -c "nnoremap <C-w>c :q!<CR>"
}

# Open a cpp & h file
function vimc() {
  vim "$1.cpp" "-c vsp $1.h"
}

alias vimtxt='vimtmp .txt'
alias vimscratch='vimtmp $(date +%Y-%m-%d-%S)'

# Start a webserver no matter the version of python. Used to be an alias:
# alias www='python -m SimpleHTTPServer 8000'
function www() {
  PORT="8000"
  if [ -z "$1" ]; then
    PORT="$1"
  fi

  PYTHON="python"
  MODULE="http.server"
  if [ $(which python3) ]; then
    PYTHON="python3"
  elif [["$(python --version)" == "Python 2.*" ]]; then
    # Everything else, which should be version 2
    MODULE="SimpleHTTPServer"
  fi

  # Invoke the command
  COMMAND="$PYTHON -m $MODULE $PORT"
  $COMMAND
}

# hide/show all desktop icons (useful when presenting)
alias hidedt="defaults write com.apple.finder createdesktop -bool false && killall finder"
alias showdt="defaults write com.apple.finder createdesktop -bool true && killall finder"

# show path line by line
alias path='echo -e ${PATH//:/\\n}'

# No reason for this, but it's a good use of shell escapes
alias timestamp='echo $(date +%Y-%m-%d-%S)'

# If I'm too lazy to hit <Ctrl-Command-Q>
alias lock='/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend'

# Let tmux support colors
alias tmux="tmux -2"

# Easy attach/ls
alias tmuxa="tmux attach-session"
alias tmuxls="tmux list-sessions"

# open man page in Preview
function pman { man -t "$1" | open -f -a Preview; }
