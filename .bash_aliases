# Easier navigation: .., ..., ...., and -
alias ..="cd .."
alias ...="cd ../.."
alias cdt="cd ~/Desktop"
alias cdesk="cd ~/Desktop"
alias cdot="cd ~/dotfiles"
alias cdev="cd ~/dev"
function bashcurl() {
  bash <(curl --silent $1)
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
