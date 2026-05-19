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
log::dev()      { echo -e "${c_cyan}[DEV]$(log::preamble)${c_rst}" "$@" >&2 ; }
log::_err()    { echo -e "${c_red}[ERROR]$(log::preamble)${c_rst}" "$@" >&2 ; }
log::err()    { log::_err "$@"; [ -n "${OTTO_ERR_LOGFILE:-}" ] && echo "$@" >> "${OTTO_ERR_LOGFILE}"; return 0; }
log::warn()  { echo -e "${c_yellow}[WARN]$(log::preamble)${c_rst}" "$@" >&2 ; }
log::info()   { echo -e "${c_green}[INFO]$(log::preamble)${c_rst}" "$@" >&2 ; }
log::_debug() { echo -e "${c_grey}[DEBUG]$(log::preamble)${c_rst}" "$@" >&2 ; }
log::debug() { case "${OTTO_DEBUG:-}" in ""|0) return 0 ;; esac; log::_debug "$@" ; }

# Multiline logs
log::DEV()   { (while IFS= read -r line; do log::dev   "| $line"; done <<< "$*") ; }
log::ERR()   { (while IFS= read -r line; do log::err   "| $line"; done <<< "$*") ; }
log::WARN()  { (while IFS= read -r line; do log::warn  "| $line"; done <<< "$*") ; }
log::INFO()  { (while IFS= read -r line; do log::info  "| $line"; done <<< "$*") ; }
log::DEBUG() { (while IFS= read -r line; do log::debug "| $line"; done <<< "$*") ; }
log::colorize_each_line() { local color="${1:-}"; while IFS= read -r line; do echo "${color}${line}${c_rst}"; done; }

# Nicer preamble
# zsh's built-in datetime module gives us $epochtime ([secs, nanosecs]) and
# `strftime`, so the preamble doesn't fork `date` on every log line.
zmodload -F zsh/datetime b:strftime p:epochtime 2>/dev/null
log::preamble() {
  test -n "${OTTO_NO_PREAMBLE:-}" && return
  local ts
  strftime -s ts "%Y-%m-%dT%H:%M:%S" "${epochtime[1]}"
  printf ' [%s.%09dZ] [%s]' "${ts}" "${epochtime[2]}" "$(log::_caller)"
}
log::is_irrelevant_fxn() {
  [ -z "${1:-}" ] && return 0 # empty function: irrelevant
  case "$1" in
    run_cmd*|fzfdb*|^_*|log::*|_log::*|*::_*) return 0 ;; # irrelevant functions
  esac
  return 1 # found a relevant function!
}
log::_caller() {
  local i=0
  while log::is_irrelevant_fxn "${funcstack[$i]:-}" && (( i++ < 10 )); do :; done
  echo -n "${funcstack[$i]:-main}"
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

# Truncate $1 (or /tmp/${OTTO_LOG_NOTIF_GROUP}.log if no arg) and tee stderr
# to it for the rest of the script. Captures every log::* call into a per-run
# logfile while still letting the caller's stderr pass through. tee path is
# absolute because zsh's command hash can be stale in script-sourced contexts.
function log::redirect_all_output_to_logfile() {
  local path="${1:-/tmp/${OTTO_LOG_NOTIF_GROUP:-log}.log}"
  : > "${path}"
  exec 2> >(/usr/bin/tee -a "${path}" >&2)
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

#######################################
# Show a terminal-notifier banner, auto-removed after a delay. Cleanup is
# spawned via `nohup` so it survives the caller's exit — no `wait` needed.
# Requires `terminal-notifier` on PATH.
# Usage: log::notify "<message>"
# Globals (all read at call time — pass via env or export at script top):
#   OTTO_LOG_NOTIF_TITLE  — title (default "notification")
#   OTTO_LOG_NOTIF_GROUP  — group ID for replacement / removal (default "default")
#   OTTO_LOG_NOTIFY_SECS  — auto-remove delay in seconds (default 5)
#   notif_lvl             — log level to also fire (info/warn/err/debug). Named
#                           distinct from `lvl` so it doesn't collide with
#                           run_cmd's level. Default: debug.
#                           Example: `notif_lvl=err log::notify "msg"`
# Returns: 1 if message is missing or terminal-notifier is not installed
#######################################
function log::notify() {
  local message="${1:?log::notify requires a message}"
  local title="${OTTO_LOG_NOTIF_TITLE:-notification}"
  local group="${OTTO_LOG_NOTIF_GROUP:-default}"
  local secs="${OTTO_LOG_NOTIFY_SECS:-5}"
  local lvl="${notif_lvl:-debug}"
  command -v terminal-notifier >/dev/null 2>&1 || { log::warn "terminal-notifier not on PATH"; return 1; }
  "log::${lvl}" "notify | secs='${secs}' group='${group}' title='${title}' message='${message}'"
  terminal-notifier -title "${title}" -message "${message}" -group "${group}" >/dev/null
  nohup zsh -c "sleep ${secs} && terminal-notifier -remove '${group}' >/dev/null 2>&1" \
    </dev/null >/dev/null 2>&1 &
}
