#######################################################################
#                                                                     #
#   .bashrc file                                                      #
#                                                                     #
#   commands to perform from the bash shell at login time             #
#                                                                     #
#######################################################################

#This was my hello-world line for learning about bash :')
echo "Today's date is `date`"
HOME_INODE=`ls -ali ~/ | sed -n 2p | sed -E 's/ ([0-9]+).*/\1/'`
echo "	Hello, user number $HOME_INODE"
echo ""

# Add to PATH
export PATH="$PATH:$HOME/.local/bin"

# Lets me run 'cd folder' to go into '~/Desktop/folder'
export CDPATH=".:$HOME/Desktop"

# When using !! or !$, command is redisplayed ready to run instead of ran
shopt -s histverify

# Prevent overwriting a file with '>', the redirect operator. You can override
# with the '>|' operator.
set -o noclobber

export EDITOR=vim

################################ History hacks ################################
# If you type a command, erase duplicates of it from history before recording it
# https://unix.stackexchange.com/questions/18212/bash-history-ignoredups-and-erasedups-setting-conflict-with-common-history
HISTCONTROL=ignoredups:erasedups
# Run these commands before evaluating $PS1. Don't cache history lines
# https://www.gnu.org/software/bash/manual/html_node/Bash-History-Builtins.html
PROMPT_COMMAND="history -n; history -w; history -c; history -r; $PROMPT_COMMAND"
export HISTSIZE=10000
# multi-line commands are saved to the history with embedded semicolons
shopt -s cmdhist
# Append, don't overwrite
shopt -s histappend

#when invoking 'ls', I'll get colors.
export LSCOLORS='exGxFxDacxDxDxHbaDacec'
export CLICOLOR=1

# hah HAAAAAH
trap 'echo lol oops - exited with $?' ERR

#If I have an alias file, then source it here
FILE="$HOME/.bash_aliases"
if [ -f $FILE ]; then
  source $FILE
fi

# Sourcing PS1 script for that dank pwd
source "$HOME/.local/bin/PS1.sh"

# If I have an npm completion script, source it
FILE="$HOME/.npm/completion.sh"
if [ -f $FILE ]; then
  source $FILE
fi
