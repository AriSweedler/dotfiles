bindkey -v
bindkey '^R' history-incremental-search-backward

# Set history stuff. https://zsh.sourceforge.io/Doc/Release/Options.html#History
setopt HIST_IGNORE_SPACE      # ignore commands that start with space
setopt HIST_EXPIRE_DUPS_FIRST # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt EXTENDED_HISTORY       # Add timestamps to history files
setopt HIST_REDUCE_BLANKS     # Trim silly whitespace from history
export HISTFILE="$XDG_STATE_HOME/zsh/history"
mkdir -p "$(dirname "$HISTFILE")"
export HISTSIZE=500000
export SAVEHIST=$HISTSIZE
export HISTORY_IGNORE

# Use a more modern way to lock the history file. Should be a net positive on
# my shiny new machine
setopt HIST_FCNTL_LOCK

# When using !! or !$, command is redisplayed ready to run instead of ran
setopt HISTVERIFY

# imports new commands from the history file, and also causes your typed
# commands to be appended to the history file immediately
setopt SHARE_HISTORY

# lines of history are of the form:
#
#     : 1728495347:0;my_cmd
#     : 1728495351:0;echo hello
#     : 1728495400:0;find . -name "file"
#
# Where the number is seconds since epoch
function histrm() {
  while (( $# > 0 )); do
    case "${1:?}" in
      --seconds) histrm::recent::seconds "${2:?}"; shift 2 ;;
      --cmd) histrm::cmd "${2:?}"; shift 2 ;;
      --lines) histrm::recent::lines "${2:?}"; shift 2 ;;
      *) histrm::recent::seconds "${1:?}"; shift ;;
    esac
  done

  # Clean up if necessary
  rm -f "${HISTFILE}.tmp"
}

function histrm::_commit() {
  local max_lines="${1:?}"
  local my_diff
  my_diff="$(diff "${HISTFILE}.tmp" "${HISTFILE}")"
  local actual_lines
  actual_lines="$(wc -l <<< "${my_diff}")"
  actual_lines=$(( actual_lines - 1 )) # Diff has a header

  if (( actual_lines > max_lines )); then
    _log::histrm::warn::rollback
    rm "${HISTFILE}.tmp"
    return 1
  fi

  log::info "Removed N lines | N='${actual_lines}'"
  mv "${HISTFILE}.tmp" "${HISTFILE}"
  histpersist::disk_to_shell

  local histrm_history="${XDG_STATE_HOME}/zsh/histrm"
  log::debug "Saving histrm history | histrm_history='${histrm_history}'"
  echo "${my_diff}" > "${XDG_STATE_HOME}/zsh/histrm"
}

# Take all lines with dates > 'X seconds ago' and remove them
function histrm::recent::seconds() {
  local seconds_ago="${1:?}"

  local now largest_ts
  now="$(date +%s)"
  largest_ts=$(( now - seconds_ago ))
  log::info "Removing all history that's less than X seconds old | X='$seconds_ago'"
  log::debug "data | now='$now' largest_ts='$largest_ts'"

  # We save the timestamp when we see a new command and skip or print every line
  # until we get to the next one. This works for multiline files
  awk -F':' -v largest_ts="$largest_ts" '
    /^: 17/ {current_ts=$2}
    (current_ts < largest_ts) {print}
  ' "${HISTFILE}" > "${HISTFILE}.tmp"

  # Commit the '.tmp' file
  histrm::_commit "${seconds_ago}"
}

# Take the N most recent lines and remove them
function histrm::recent::lines() {
  local lines="${1:?}"
  lines=$((lines++))
  # The command to invoke this adds a line to the history file - so if we ask to
  # delete N entries, we need to remove N+1 lines (assuming none are multiline!)
  log::info "Removing the last N lines from history | N='$lines'"
  tac "${HISTFILE}" | sed "1,${lines}d" | tac > "${HISTFILE}.tmp"
  histrm::_commit "${lines}"
}

# Take all lines with a specific command and remove them
function histrm::cmd() {
  if ! awk -F';' -v cmd="$1" '
    $2 == cmd { next }
    $2 ~ "histrm \".*\"" { next }
    {print}
  ' "${HISTFILE}" > "${HISTFILE}.tmp"; then
    log::err "Failed to remove line from history"
    rm "${HISTFILE}.tmp"
    return
  fi

  histrm::_commit 20
}

# Take loaded history and persist it to disk
function histpersist::shell_to_disk() {
  fc -W
}

# Take disk history and load it to shell
function histpersist::disk_to_shell() {
  fc -R
}

function _log::histrm::warn::rollback() {
  log::WARN "
This command would delete too many lines... something is wrong

    actual_lines='${actual_lines}'
    max_lines='${max_lines}'

30 lines of my diff:

$(_indent 4 <<< "${my_diff}" | head -30)
"
}
