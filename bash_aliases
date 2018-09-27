#when invoking 'ls', I'll get colors.
export LSCOLORS='exGxFxDacxDxDxHbaDacec'
export CLICOLOR=1

#small aliases
alias prolog='swipl'
alias pwdd='. cowsay-pwd'
alias fortunee='. cowsay-fortune'
alias vi=vim
alias league="open -jF /Applications/League\ of\ Legends.app"
alias music="open -jF /Applications/Spotify.app"

#my aliases to help me cd around
alias work='cd $(cat ~/.config/work)'
alias tensorflow='echo ""; cd $HOME/Library/VirtualEnv; source bin/activate'

#my aliases to help me mount/unmount
alias mount-lnxsrv='myMount ucla /u/cs/ugrad/ari/Classes/'
alias mount-bb='myMount bb /root'
alias mount-bbu='myMount bbu /Users/ari'
alias unmount-lnxsrv='myUnmount ucla'
alias unmount-bb='myUnmount bb'
alias unmount-bbu='myUnmount bbu'
#shortened versions
alias ml='mount-lnxsrv'
alias mbb='mount-bb'
alias mbbu='mount-bbu'

# Easier navigation: .., ..., ...., ....., ~ and -
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ~="cd ~" # `cd` is probably faster to type though
alias -- -="cd -"

alias mongod="echo \"   running mongod with config file: $MONGOD_CONF\";sudo mongod -f \"$MONGOD_CONF\""
alias scheme="echo '        rlwrap enabled';rlwrap scheme"
alias ocaml="echo '        rlwrap enabled';rlwrap ocaml"
