# The classic log suite
c_red='\e[31m'
c_green='\e[32m'
c_yellow='\e[33m'
c_rst='\e[0m'

preamble() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [$funcstack[3]]" ; }
log::err() { echo -e "${c_red}[ERROR] $(preamble)${c_rst}" "$@" >&2 ; }
log::info() { echo -e "${c_green}[INFO] $(preamble)${c_rst}" "$@" ; }
log::warn() { echo -e "${c_yellow}[WARN] $(preamble)${c_rst}" "$@" >&2 ; }

run_cmd() {
  log::info "$@"
  "$@" && return
  rc=$?
  log::err "cmd '$*' failed: $rc"
  return $rc
}
