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

#Setting PATH
export PATH="$PATH:$HOME/bin"

export EDITOR=vim

#Surprisingly this is actually v useful
export HISTIGNORE="[ \t]*"
export HISTSIZE=5000
export HISTCONTROL=ignoreboth:erasedups

#If I have an alias file, then source it here
FILE="$HOME/.bash_aliases"
if [ -f $FILE ]; then
  source $FILE
fi

# Sourcing PS1 script for that dank pwd
source "$HOME/.bash_prompt"

# If I have an npm completion script, source it
FILE="$HOME/.npm/completion.sh"
if [ -f $FILE ]; then
  source $FILE
fi
