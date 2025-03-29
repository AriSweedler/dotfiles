# The classic log suite
c_red='\033[31m'; c_green='\033[32m'; c_yellow='\033[33m';
c_cyan='\033[36m'; c_grey='\033[90m'; c_rst='\033[0m'
log::is_irrelevant_fxn() {
  [ -z "${1:-}" ] && return 0 # empty function: irrelevant
  case "$1" in
    run_cmd*|log::*|_log::*|*::_*) return 0 ;; # irrelevant functions
  esac
  return 1 # found a relevant function!
}
log::preamble() {
  local -r date=$(date "+%Y-%m-%dT%T.000Z")

  local fxn=main i=0
  while log::is_irrelevant_fxn "${FUNCNAME[$i]}" && (( i++ < 10 )); do :; done
  local fxn=${FUNCNAME[$i]}
  local line=${BASH_LINENO[$((i-1))]}
  # local src="${BASH_SOURCE[$i]#${OTTO_REPO_ROOT}/bash_lib/}"

  echo -n "[${date}] [${fxn}+${line}]"
}
[ -n "${OTTO_DISABLE_PREAMBLE:-}" ] && log::preamble() { :; }

# Colorize and send to stderr
log::dev()      { echo -e "${c_cyan}[DEV] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::_err()    { echo -e "${c_red}[ERROR] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::err()    { log::_err "$@"; [ -n "${OTTO_ERR_LOGFILE:-}" ] && echo "$@" >> "${OTTO_ERR_LOGFILE}" ; }
log::warn()  { echo -e "${c_yellow}[WARN] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::info()   { echo -e "${c_green}[INFO] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::_debug() { echo -e "${c_grey}[DEBUG] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::debug() { otto::is_true "${OTTO_DEBUG:-}" || return 0; log::_debug "$@" ; }

# Multiline
log::DEV()   { (while IFS= read -r line; do log::dev   "| $line"; done <<< "$*") ; }
log::ERR()   { (while IFS= read -r line; do log::_err  "| $line"; done <<< "$*") ; }
log::WARN()  { (while IFS= read -r line; do log::warn  "| $line"; done <<< "$*") ; }
log::INFO()  { (while IFS= read -r line; do log::info  "| $line"; done <<< "$*") ; }
log::DEBUG() { (while IFS= read -r line; do log::debug "| $line"; done <<< "$*") ; }

# Running commands
function run_cmd_cap() {
  o="$(run_cmd "$@")"
  rc=$?
  (( rc == 0 )) && log::${lvl:-INFO} "${o}"
  (( rc != 0 )) && log::${lvl_fail:-ERR} "${o}"
  return $rc
}

function run_cmd() {
  "log::${lvl:-info}" "$@"
  "$@" && return; rc=$?
  set -- $(printf "'%s' " "$@")
  "log::${lvl_fail:-ERR}" "cmd failed | rc=$rc cmd_quoted=|$*|"
  return $rc
}

# Debugging
function log::dev::trace() {
  log::dev "We just invoked function with args | func='${FUNCNAME[1]}'"
  local i=0
  for arg in "$@"; do log::dev "arg | \$$((++i))='${arg}'"; done
}
