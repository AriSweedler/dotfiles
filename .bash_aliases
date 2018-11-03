#when invoking 'ls', I'll get colors.
export LSCOLORS='exGxFxDacxDxDxHbaDacec'
export CLICOLOR=1

#small aliases
alias pwdd='. cowsay-pwd'
alias fortunee='. cowsay-fortune'
alias vi=vim
alias league="open -jF /Applications/League\ of\ Legends.app"
alias music="open -jF /Applications/Spotify.app"

#my aliases to help me cd around
alias work='cd $(cat ~/.config/work)'

# Easier navigation: .., ..., ...., and -
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias -- -="cd -"

alias qemu="qemu-system-x86_64"

# start a webserver
alias www='python -m SimpleHTTPServer 8000'
