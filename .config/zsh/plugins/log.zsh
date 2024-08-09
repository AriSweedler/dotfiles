# The classic log suite
c_red='\e[31m'
c_green='\e[32m'
c_yellow='\e[33m'
c_cyan='\e[36m'
c_rst='\e[0m'

bash_preamble() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [${BASH_SOURCE[2]}]" ; }
preamble() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [$funcstack[3]]" ; }
log::dev() { echo -e "${c_cyan}[DEV] $(preamble)${c_rst}" "$@" >&2 ; }
log::err() { echo -e "${c_red}[ERROR] $(preamble)${c_rst}" "$@" >&2 ; }
log::info() { echo -e "${c_green}[INFO] $(preamble)${c_rst}" "$@" >&2 ; }
log::debug() { [ -n "$ARI_DEBUG" ] && echo -e "${c_grey}[DEBUG] $(preamble)${c_rst}" "$@" >&2 ; }
log::warn() { echo -e "${c_yellow}[WARN] $(preamble)${c_rst}" "$@" >&2 ; }

run_cmd() {
  log::${lvl:-info} "$@"
  "$@" && return
  rc=$?
  log::${lvl_fail:-err} "cmd '$*' failed: $rc"
  return $rc
}

function log::DEV() {
  while read -r line; do log::dev "$line"; done <<< "$*"
}

function log::ERR() {
  while read -r line; do log::err "$line"; done <<< "$*"
}

function log::WARN() {
  while read -r line; do log::warn "$line"; done <<< "$*"
}

function log::INFO() {
  while read -r line; do log::info "$line"; done <<< "$*"
}

function log::DEBUG() {
  while read -r line; do log::debug "$line"; done <<< "$*"
}
