bindkey -v
bindkey '^R' history-incremental-search-backward

# Set history stuff. https://zsh.sourceforge.io/Doc/Release/Options.html#History
#
setopt HIST_IGNORE_SPACE      # ignore commands that start with space
setopt HIST_EXPIRE_DUPS_FIRST # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt EXTENDED_HISTORY       # Add timestamps to history files
setopt HIST_REDUCE_BLANKS     # Trim silly whitespace from history
export HISTFILE="$HOME/.histfile"
export HISTSIZE=500000
export SAVEHIST=$HISTSIZE

# Use a more modern way to lock the history file. Should be a net positive on
# my shiny new machine
setopt HIST_FCNTL_LOCK

# When using !! or !$, command is redisplayed ready to run instead of ran
setopt HISTVERIFY

# imports new commands from the history file, and also causes your typed
# commands to be appended to the history file immediately
setopt SHARE_HISTORY

# Remove a line from your history dir
function histrm() {
  # Ensure there is 1 arg
  if (( $# != 1 )); then
    log::err "Only give 1 arg to 'histrm'"
    return 1
  fi

  local tmp_file=$(mktemp)
  if ! awk -F';' -v cmd="$1" '
    $2 == cmd {
      removed++
      print "Deleting line: " $0 > "/dev/stderr"
      next
    }
    $2 ~ "histrm \".*\"" {
      print "Deleting histrm line: " $0 > "/dev/stderr"
      next
    }
    {print}
    END {
      if (removed) {
        print "Deleted " removed " lines" > "/dev/stderr"
      } else {
        print "No lines deleted" > "/dev/stderr"
      }
    }
  ' "$HISTFILE" > "$tmp_file"; then
    log::err "Failed to remove line from history"
    rm "$tmp_file"
    return
  fi

  mv "$tmp_file" "$HISTFILE"
}
