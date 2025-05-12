# Colors
c_red='\033[31m'
c_green='\033[32m'
c_yellow='\033[33m'
c_blue='\033[34m'
c_magenta='\033[35m'
c_cyan='\033[36m'
c_white='\033[37m'
c_grey='\033[90m'
c_rst='\033[0m'

# Colorize and send to stderr.
# Send err to OTTO_ERR_LOGFILE if that env var is set
log::dev()      { echo -e "${c_cyan}[DEV] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::_err()    { echo -e "${c_red}[ERROR] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::err()    { log::_err "$@"; [ -n "${OTTO_ERR_LOGFILE:-}" ] && echo "$@" >> "${OTTO_ERR_LOGFILE}"; return 0; }
log::warn()  { echo -e "${c_yellow}[WARN] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::info()   { echo -e "${c_green}[INFO] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::_debug() { echo -e "${c_grey}[DEBUG] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::debug() { test -f "${OTTO_DEBUG:-}" || return 0; log::_debug "$@" ; }

# Multiline logs
log::DEV()   { (while IFS= read -r line; do log::dev   "| $line"; done <<< "$*") ; }
log::ERR()   { (while IFS= read -r line; do log::err   "| $line"; done <<< "$*") ; }
log::WARN()  { (while IFS= read -r line; do log::warn  "| $line"; done <<< "$*") ; }
log::INFO()  { (while IFS= read -r line; do log::info  "| $line"; done <<< "$*") ; }
log::DEBUG() { (while IFS= read -r line; do log::debug "| $line"; done <<< "$*") ; }

# Nicer preamble
log::preamble()       { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [$(log::_caller)]" ; }
log::is_irrelevant_fxn() {
  [ -z "${1:-}" ] && return 0 # empty function: irrelevant
  case "$1" in
    run_cmd*|fzfdb*|^_*|log::*|_log::*|*::_*) return 0 ;; # irrelevant functions
  esac
  return 1 # found a relevant function!
}
log::_caller() {
  local i=0
  while log::is_irrelevant_fxn "${funcstack[$i]}" && (( i++ < 10 )); do :; done
  echo -n "${funcstack[$i]}"
}

# Log the running commands
export lvl=INFO
export lvl_fail=ERR
function run_cmd() {
  # Log the command, exit early if it succeeds
  "log::${lvl}" "$@"
  "$@" && return
  rc=$?
  # Log the failure with th ecommand quoted. Forward the rc
  set -- $(printf "'%s' " "$@")
  "log::${lvl_fail}" "cmd failed | rc=$rc cmd_quoted=|$*|"
  return $rc
}

# Log the running command and capture the stdout only (allow stderr - which
# probably contains logs - through)
function run_cmd_cap() {
  o="$(run_cmd "$@")"
  rc=$?
  (( rc == 0 )) && log::${lvl} "${o}"
  (( rc != 0 )) && log::${lvl_fail} "${o}"
  return $rc
}
