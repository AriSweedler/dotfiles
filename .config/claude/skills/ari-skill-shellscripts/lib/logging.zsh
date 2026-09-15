#!/usr/bin/env zsh
# Canonical colorized logging for skill zsh scripts. Source it; do not execute.
#
#   readonly SCRIPT_DIR="${0:A:h}"
#   readonly SKILLS_DIR="${SCRIPT_DIR:h:h}"   # script in <skill>/bin/ or <skill>/lib/ (add :h per extra nesting)
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
#
# Tiers (all write to stderr; stdout is reserved for data):
#   log::info/warn/err/ok/dev/debug   single-line
#   log::INFO/WARN/ERR/DEV/DEBUG      multi-line — one log line per input line, '|'-prefixed
#   run_cmd / run_cmd_cap            run a command, logging before + on failure
#
# Conventions (see ari-skill-shellscripts SKILL.md): separate message from data
# with '|'; never interpolate values into the message; key name matches var name.
#   GOOD: log::err "Invalid mode | mode='${mode}' valid='${(j:, :)VALID}'"
#
# Compatibility knobs:
#   VERBOSE=true        enable log::debug
#   AT_DEBUG=<file>     enable log::debug when the file exists
#   AT_ERR_LOGFILE=<f>  log::err also appends the message to this file
#   lvl / lvl_fail      run_cmd success/failure tiers (default INFO / ERR)

# Include guard: the `readonly` colors below would abort a re-source under `set -e`.
[[ -n "${_ARI_LOGGING_ZSH:-}" ]] && return 0
readonly _ARI_LOGGING_ZSH=1

# --- Colors (union across skills; $'..' embeds the real ESC so plain echo works) ---

readonly c_red=$'\e[31m' c_green=$'\e[32m' c_yellow=$'\e[33m' c_blue=$'\e[34m' \
         c_magenta=$'\e[35m' c_cyan=$'\e[36m' c_white=$'\e[37m' c_grey=$'\e[90m' \
         c_bold=$'\e[1m' c_rst=$'\e[0m'

# --- Single-line tiers ---

log::info() { echo "${c_green}[INFO]${c_rst} $*" >&2; }
log::warn() { echo "${c_yellow}[WARN]${c_rst} $*" >&2; }
log::ok()   { echo "${c_green}[OK]${c_rst} $*" >&2; }
log::dev()  { echo "${c_cyan}[DEV]${c_rst} $*" >&2; }
# `return 0` so `set -e` callers don't abort, and so the optional tee can't fail the call.
log::err()  { echo "${c_red}[ERROR]${c_rst} $*" >&2; [[ -n "${AT_ERR_LOGFILE:-}" ]] && echo "$*" >> "${AT_ERR_LOGFILE}"; return 0; }
log::debug() { { [[ "${VERBOSE:-false}" == "true" ]] || [[ -f "${AT_DEBUG:-}" ]]; } && echo "${c_grey}[DEBUG]${c_rst} $*" >&2; return 0; }

# Underscore aliases kept for callers that used the raw variants.
log::_err()   { log::err "$@"; }
log::_debug() { log::debug "$@"; }

# Timestamp preamble for callers that print it explicitly (the standard tiers
# above omit it). Suppressed when AT_LOG_SKIP_PREAMBLE is set.
log::preamble() { [[ -n "${AT_LOG_SKIP_PREAMBLE:-}" ]] && return 0; echo -n "[$(date "+%Y-%m-%dT%T.000Z")]"; }

# --- Multi-line tiers (one log line per input line, '|'-prefixed) ---

log::INFO()  { while IFS= read -r line; do log::info  "| ${line}"; done <<< "${*}"; }
log::WARN()  { while IFS= read -r line; do log::warn  "| ${line}"; done <<< "${*}"; }
log::ERR()   { while IFS= read -r line; do log::err   "| ${line}"; done <<< "${*}"; }
log::DEV()   { while IFS= read -r line; do log::dev   "| ${line}"; done <<< "${*}"; }
log::DEBUG() { while IFS= read -r line; do log::debug "| ${line}"; done <<< "${*}"; }

# --- Command execution with logging ---

# Mutable so callers can override per-invocation: `lvl=DEBUG lvl_fail=ERR run_cmd ...`.
: "${lvl:=INFO}"
: "${lvl_fail:=ERR}"

run_cmd() {
  "log::${lvl}" "running | cmd='${*}'"
  "${@}" && return
  local rc="${?}"
  "log::${lvl_fail}" "cmd failed | rc='${rc}' cmd='${*}'"
  return "${rc}"
}

# Like run_cmd but also logs the command's captured stdout.
run_cmd_cap() {
  local out rc
  out="$(run_cmd "${@}")"; rc="${?}"
  (( rc == 0 )) && "log::${lvl}" "${out}"
  (( rc != 0 )) && "log::${lvl_fail}" "${out}"
  return "${rc}"
}
