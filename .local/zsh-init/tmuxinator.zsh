# Start the week
alias monday='tmuxinator work'

# Open up a playground
function playground() {
  local -r play_exe="/Users/arisweedler/workspace/playground/play"
  if (( $# != 2 )); then
    log_err "Need 2 arguments to '$funcstack[1]'"
    echo
    "$play_exe" help
    return 1
  fi
  tmuxinator playground "$@"
}
