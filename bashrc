echo "in ~/.bashrc"

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

#Setting PATH
export PATH="$PATH:$HOME/bin"
export PATH="$PATH:$HOME/Applications/apache-maven-3.5.3/bin"
export PATH="$PATH:/mongodb/bin"

export EDITOR=vim

#Surprisingly this is actually v useful
HISTIGNORE="&:[ \t]*:ls:cat:less"
HISTSIZE=5000

#If I have an alias file, then source it here
if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

MONGOD_CONF="/etc/mongodb.conf"

# Sourcing PS1 script for that dank pwd
. "$HOME/bin/.bash_prompt"
