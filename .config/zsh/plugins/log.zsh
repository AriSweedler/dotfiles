# The classic log suite
c_red='\e[31m'; c_green='\e[32m'; c_yellow='\e[33m'; c_cyan='\e[36m'; c_rst='\e[0m'
log::preamble::bash() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [${BASH_SOURCE[2]}]" ; }
log::preamble()       { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [$funcstack[3]]" ; }

log::dev()      { echo -e "${c_cyan}[DEV] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::err()     { echo -e "${c_red}[ERROR] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::warn()  { echo -e "${c_yellow}[WARN] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::info()   { echo -e "${c_green}[INFO] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::_debug() { echo -e "${c_grey}[DEBUG] $(log::preamble)${c_rst}" "$@" >&2 ; }
log::debug() { [ -z "${DEBUG:-}" ] && return; log::_debug "$@" ; }

# Multiline logs
log::DEV()   { while read -r line; do log::dev   "$line"; done <<< "$*" ; }
log::ERR()   { while read -r line; do log::err   "$line"; done <<< "$*" ; }
log::WARN()  { while read -r line; do log::warn  "$line"; done <<< "$*" ; }
log::INFO()  { while read -r line; do log::info  "$line"; done <<< "$*" ; }
log::DEBUG() { while read -r line; do log::debug "$line"; done <<< "$*" ; }

# Running commands
function run_cmd() {
  log::${lvl:-info} "$@"
  "$@" && return; rc=$?
  set -- $(printf "'%s' " "$@")
  log::${lvl_fail:-ERR} "cmd failed | rc=$rc cmd_quoted=|$*|"
  return $rc
}

# String manipulation
function _prepend() {
  [ -t 0 ] && return 1
  while read -r line; do echo "${1:?}${line}"; done
}
function _indent() {
  local indent=""
  for ((i="${1:?}"; i-->0;)); indent+=" "
  _prepend "${indent}"
}
