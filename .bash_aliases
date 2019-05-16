# Easier navigation
alias ..="cd .."
alias ...="cd ../.."
alias cdt="cd ~/Desktop"
alias cdesk="cd ~/Desktop"
alias cdot="cd ~/dotfiles"

function cdev() {
  if [ -z "$1" ]; then
    cd ~/dev
  else
    cd ~/dev/"$1"* || cd ~/dev; ls
  fi
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
alias vimscratch='vimtmp $(date +%Y-%m-%d-%S)'

# start a webserver
alias www='python -m SimpleHTTPServer 8000'

# hide/show all desktop icons (useful when presenting)
alias hidedt="defaults write com.apple.finder createdesktop -bool false && killall finder"
alias showdt="defaults write com.apple.finder createdesktop -bool true && killall finder"

# show path line by line
alias path='echo -e ${PATH//:/\\n}'

# No reason for this, but it's a good use of shell escapes
alias timestamp='echo $(date +%Y-%m-%d-%S)'

# If I'm too lazy to hit <Ctrl-Command-Q>
alias lock='/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend'

# make tmux support colors
alias tmux="tmux -2"

# open man page in Preview
function pman { man -t "$1" | open -f -a Preview; }
