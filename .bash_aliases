# Easier navigation
alias ..="cd .."
alias ...="cd ../.."
alias cdt="cd ~/Desktop"
alias cdesk="cd ~/Desktop"
alias cdot="cd ~/dotfiles"
alias cdev="cd ~/dev"
function bashcurl() {
  bash <(curl --silent $1)
}

# read vim help pages straight from terminal. Allow exiting with 'c'
function vimhelp() {
  vim -c "help $1" -c "only" -c "nnoremap <C-w>c :q!<CR>"
}

# TODO do I want a new folder each invocation?
# TODO do I want a new file each invocation?
# Should TMPDIR be in /tmp?
# What arguments will I wanna add?
  # File name
  # File extension (.txt as $1 ==> scratch.txt)
function vimtmp()  {
  TMPDIR="$HOME/vim-tmp"
  mkdir -p $TMPDIR
  pushd $TMPDIR
  vim "$TMPDIR/scratch${1}"
  popd
}
alias vimtxt='vimtmp .txt'

# Run a job in a new terminal window - useful for stuff like git push
function newWindow() {
  osascript -e '
  tell application "Terminal"
    do script "cd '$PWD'; '"$*"'"
  end tell
  '
}

# start a webserver
alias www='python -m SimpleHTTPServer 8000'

# hide/show all desktop icons (useful when presenting)
alias hidedt="defaults write com.apple.finder createdesktop -bool false && killall finder"
alias showdt="defaults write com.apple.finder createdesktop -bool true && killall finder"

# show path line by line
alias path='echo -e ${PATH//:/\\n}'

# If I'm too lazy to hit <Ctrl-Command-Q>
alias lock='/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend'

# make tmux support colors
alias tmux="tmux -2"

# open man page in Preview
function pman { man -t "$1" | open -f -a Preview; }
