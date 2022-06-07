# Set history stuff. https://zsh.sourceforge.io/Doc/Release/Options.html#History
#
setopt HIST_IGNORE_SPACE      # ignore commands that start with space
setopt HIST_EXPIRE_DUPS_FIRST # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt EXTENDED_HISTORY       # Add timestamps to history files
setopt HIST_REDUCE_BLANKS     # Trim silly whitespace from history
export HISTFILE="$HOME/.histfile"
export HISTSIZE=50000
export SAVEHIST=$HISTSIZE

# Use a more modern way to lock the history file. Should be a net positive on
# my shiny new machine
setopt HIST_FCNTL_LOCK

# When using !! or !$, command is redisplayed ready to run instead of ran
setopt HISTVERIFY

# imports new commands from the history file, and also causes your typed
# commands to be appended to the history file immediately
setopt SHARE_HISTORY
