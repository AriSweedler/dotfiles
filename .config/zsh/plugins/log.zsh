# log — the one logging library: sourced by every interactive shell, by the bins under
# ~/.config/bin, by the dotfiles harness and its steps, and (through a shim) by every skill script.
# Every tier writes to stderr; stdout stays data. Message and data are separated by ' | ' and
# data is key='value', so a line greps the same way everywhere:
#   log::info "Pushing | repo='${repo}' sha='${sha}'"
#
# Tiers:   log::info|warn|err|ok|dev|debug   one line
#          log::INFO|WARN|ERR|DEV|DEBUG      one line per input line, '| '-prefixed
#          run_cmd / run_cmd_cap             run a command, logging before and on failure
# Knobs (all optional):
#   LOG_PREAMBLE=1|0   '[ts] [caller]' after the tag. Default: on when stderr is not a tty
#                      (log files, launchd), off on a terminal. OTTO_NO_PREAMBLE and
#                      AT_LOG_SKIP_PREAMBLE also turn it off.
#   VERBOSE=true, OTTO_DEBUG=1, AT_DEBUG=<existing file>   turn log::debug on
#   OTTO_ERR_LOGFILE / AT_ERR_LOGFILE   log::err also appends the bare message there
#   NO_COLOR, or stderr not a tty        colours off at source time; log::colors_on|off flips
#   lvl=INFO lvl_fail=ERR                run_cmd's tiers, per call: `lvl=DEBUG run_cmd …`
# Colours are real escape bytes ($'\e[..'), so a heredoc renders them; they are plain variables,
# never readonly, so the lib can be sourced again and a caller can blank them.
zmodload -F zsh/datetime b:strftime p:epochtime 2>/dev/null

log::colors_on() {
  c_red=$'\e[31m' c_green=$'\e[32m' c_yellow=$'\e[33m' c_blue=$'\e[34m' c_magenta=$'\e[35m'
  c_cyan=$'\e[36m' c_white=$'\e[37m' c_grey=$'\e[90m' c_bold=$'\e[1m' c_rst=$'\e[0m'
}
log::colors_off() {
  c_red='' c_green='' c_yellow='' c_blue='' c_magenta='' c_cyan='' c_white='' c_grey='' c_bold='' c_rst=''
}
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then log::colors_on; else log::colors_off; fi

# --- Preamble: ' [ts] [caller]', fork-free (strftime + funcstack), or nothing ---
log::is_preamble_on() {
  [[ -n "${OTTO_NO_PREAMBLE:-}" || -n "${AT_LOG_SKIP_PREAMBLE:-}" ]] && return 1
  case "${LOG_PREAMBLE:-}" in
    1|true|on) return 0 ;;
    0|false|off) return 1 ;;
  esac
  [[ ! -t 2 ]]
}
log::is_irrelevant_fxn() {
  [[ -z "${1:-}" ]] && return 0
  case "${1}" in
    run_cmd*|run_mut|fzfdb*|^_*|log::*|_log::*|*::_*) return 0 ;;
  esac
  return 1
}
log::_caller() {
  local i=0
  while log::is_irrelevant_fxn "${funcstack[$i]:-}" && (( i++ < 10 )); do :; done
  print -rn -- "${funcstack[$i]:-main}"
}
log::preamble() {
  log::is_preamble_on || return 0
  local ts
  strftime -s ts "%Y-%m-%dT%H:%M:%S" "${epochtime[1]}"
  printf ' [%s.%09dZ] [%s]' "${ts}" "${epochtime[2]}" "$(log::_caller)"
}

# --- Single-line tiers ---
log::_line() { local color="${1}" tag="${2}"; shift 2; print -r -- "${color}${tag}$(log::preamble)${c_rst} $*" >&2; }
log::info()  { log::_line "${c_green}"  '[INFO]'  "$@"; }
log::ok()    { log::_line "${c_green}"  '[OK]'    "$@"; }
log::warn()  { log::_line "${c_yellow}" '[WARN]'  "$@"; }
log::dev()   { log::_line "${c_cyan}"   '[DEV]'   "$@"; }
# Returns 0 so `set -e` callers never abort on a log line.
log::err() {
  log::_line "${c_red}" '[ERROR]' "$@"
  local f="${OTTO_ERR_LOGFILE:-${AT_ERR_LOGFILE:-}}"
  [[ -n "${f}" ]] && print -r -- "$*" >> "${f}"
  return 0
}
log::is_debug_on() {
  [[ "${VERBOSE:-}" == (true|1) ]] && return 0
  [[ -n "${OTTO_DEBUG:-}" && "${OTTO_DEBUG}" != 0 ]] && return 0
  [[ -n "${AT_DEBUG:-}" && -f "${AT_DEBUG}" ]]
}
log::debug() { log::is_debug_on || return 0; log::_line "${c_grey}" '[DEBUG]' "$@"; }
log::_err()   { log::err "$@"; }
log::_debug() { log::debug "$@"; }

# --- Multi-line tiers ---
log::_lines() { local tier="${1}"; shift; local line; while IFS= read -r line; do "log::${tier}" "| ${line}"; done <<< "$*"; }
log::INFO()  { log::_lines info  "$@"; }
log::WARN()  { log::_lines warn  "$@"; }
log::ERR()   { log::_lines err   "$@"; }
log::DEV()   { log::_lines dev   "$@"; }
log::DEBUG() { log::_lines debug "$@"; }
log::colorize_each_line() { local color="${1:-}" line; while IFS= read -r line; do print -r -- "${color}${line}${c_rst}"; done; }

# --- Command execution with logging ---
run_cmd() {
  "log::${lvl:-INFO}" "running | cmd='$*'"
  "$@" && return 0
  local rc=$?
  "log::${lvl_fail:-ERR}" "cmd failed | rc='${rc}' cmd='$*'"
  return "${rc}"
}
# Like run_cmd, and also logs the command's captured stdout (stderr passes through).
run_cmd_cap() {
  local out rc=0
  out="$(run_cmd "$@")" || rc=$?
  if (( rc == 0 )); then "log::${lvl:-INFO}" "${out}"; else "log::${lvl_fail:-ERR}" "${out}"; fi
  return "${rc}"
}

# Truncate $1 (default /tmp/${OTTO_LOG_NOTIF_GROUP}.log) and tee stderr into it for the rest of
# the script; the caller's stderr still passes through. tee by absolute path: the command hash
# can be stale in script-sourced contexts.
log::redirect_all_output_to_logfile() {
  local file="${1:-/tmp/${OTTO_LOG_NOTIF_GROUP:-log}.log}"
  : > "${file}"
  exec 2> >(/usr/bin/tee -a "${file}" >&2)
}

#######################################
# A terminal-notifier banner, removed after a delay by a nohup'd sleeper so the caller may exit.
# Globals: OTTO_LOG_NOTIF_TITLE (default "notification"), OTTO_LOG_NOTIF_GROUP (default
# "default"), OTTO_LOG_NOTIFY_SECS (default 5), notif_lvl (the tier that also logs it; debug).
# Returns 1 when the message is missing or terminal-notifier is not on PATH.
#######################################
log::notify() {
  local message="${1:?log::notify requires a message}"
  local title="${OTTO_LOG_NOTIF_TITLE:-notification}" group="${OTTO_LOG_NOTIF_GROUP:-default}"
  local secs="${OTTO_LOG_NOTIFY_SECS:-5}" tier="${notif_lvl:-debug}"
  command -v terminal-notifier >/dev/null 2>&1 || { log::warn "terminal-notifier not on PATH"; return 1; }
  "log::${tier}" "notify | secs='${secs}' group='${group}' title='${title}' message='${message}'"
  terminal-notifier -title "${title}" -message "${message}" -group "${group}" >/dev/null
  nohup zsh -c "sleep ${secs} && terminal-notifier -remove '${group}' >/dev/null 2>&1" </dev/null >/dev/null 2>&1 &
}
