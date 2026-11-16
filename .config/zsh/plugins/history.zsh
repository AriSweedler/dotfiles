bindkey -v
bindkey '^R' history-incremental-search-backward

# Set history stuff. https://zsh.sourceforge.io/Doc/Release/Options.html#History
setopt HIST_EXPIRE_DUPS_FIRST # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt EXTENDED_HISTORY       # Add timestamps to history files
setopt HIST_REDUCE_BLANKS     # Trim silly whitespace from history
export HISTFILE="$XDG_STATE_HOME/zsh/history"
mkdir -p "$(dirname "$HISTFILE")"
export HISTSIZE=500000
export SAVEHIST=$HISTSIZE

# Commands that should never enter history, matched on the first word so both
# `tcap` and `tcap <args>` are caught.
typeset -ga HIST_IGNORED_CMDS=(
  tcap
)

# A built-in Zsh hook that runs just before a line is saved. A non-zero return
# drops the line from both the on-disk file AND this shell's live history, so
# `echo hi; tcap; <Up>` recalls `echo hi`. HISTORY_IGNORE only filters the disk
# write and leaves the command in up-arrow, which is the bug we're avoiding.
zshaddhistory() {
  # Skip any command that starts with whitespace (space, tab, newline, …).
  # HIST_IGNORE_SPACE only catches a literal space, so we do it ourselves.
  [[ $1 == [[:space:]]* ]] && return 1

  local -a words; words=(${(z)1})
  (( ${HIST_IGNORED_CMDS[(Ie)$words[1]]} )) && return 1

  return 0
}

# Use a more modern way to lock the history file. Should be a net positive on
# my shiny new machine
setopt HIST_FCNTL_LOCK

# When using !! or !$, command is redisplayed ready to run instead of ran
setopt HISTVERIFY

# imports new commands from the history file, and also causes your typed
# commands to be appended to the history file immediately
setopt SHARE_HISTORY

function hist::yank() {
  fc -ln -1 | pbcopy
  log::INFO "
Copied last command to clipboard.
You're such a good coworker!
Thanks for helping your friends

    $(pbpaste)
"
}
alias hy=hist::yank
