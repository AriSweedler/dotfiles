#!/usr/bin/env zsh
# mode.zsh — the on/off state of operator mode, kept on disk so a compaction cannot lose it: a marker
# file per Claude session under /tmp/operator-mode. Every reply in a session asks `status`; nothing is
# inferred from the transcript. Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly ACTIONS=(on off status)
readonly EXIT_OFF=3

help() {
  cat <<HELP
${c_green}mode.zsh${c_rst} — switch operator mode on or off for this Claude session, or ask

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/mode.zsh on
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/mode.zsh off
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/mode.zsh status

${c_bold}Options:${c_rst}
  --session ID   the Claude session (default: \$CLAUDE_CODE_SESSION_ID)
  --root DIR     where the markers live (default: /tmp); the marker is DIR/operator-mode/ON-<session>
  -h, --help     this help

${c_bold}Output:${c_rst} one line, mode=on or mode=off, plus since=<UTC time> when on.
${c_bold}Exit codes:${c_rst} 0 on (for status) or done (for on/off); ${EXIT_OFF} off (status only); 1 a bad call.
  on and off are idempotent: a second on keeps the first since=, a second off is a no-op.
HELP
}

# --- Parse ---

action='' session="${CLAUDE_CODE_SESSION_ID:-}" root_dir='/tmp'
while (( $# > 0 )); do
  case "${1}" in
    on|off|status) action="${1}"; shift ;;
    --session) session="${2:?--session requires a value}"; shift 2 ;;
    --root) root_dir="${2:?--root requires a value}"; shift 2 ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown argument | arg='${1}' actions='${(j:, :)ACTIONS}'"; help; exit 1 ;;
  esac
done

# --- Validate ---

if [[ -z "${action}" ]]; then log::err "An action is required | actions='${(j:, :)ACTIONS}'"; help; exit 1; fi
if [[ -z "${session}" ]]; then log::err "No session: set CLAUDE_CODE_SESSION_ID or pass --session"; exit 1; fi

readonly MARKER="${root_dir}/operator-mode/ON-${session}"

# --- Logic ---

mode_on() {
  if [[ -f "${MARKER}" ]]; then
    log::info "Operator mode already on | session='${session}' since='$(<"${MARKER}")'"
  else
    mkdir -p "${MARKER:h}"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${MARKER}"
    log::info "Operator mode on | session='${session}' marker='${MARKER}'"
  fi
  print -r -- "mode=on"
  print -r -- "since=$(<"${MARKER}")"
}

mode_off() {
  if [[ -f "${MARKER}" ]]; then
    rm -f "${MARKER}"
    log::info "Operator mode off | session='${session}'"
  else
    log::info "Operator mode was already off | session='${session}'"
  fi
  print -r -- "mode=off"
}

mode_status() {
  if [[ -f "${MARKER}" ]]; then
    print -r -- "mode=on"
    print -r -- "since=$(<"${MARKER}")"
    return 0
  fi
  print -r -- "mode=off"
  return "${EXIT_OFF}"
}

case "${action}" in
  on) mode_on ;;
  off) mode_off ;;
  status) mode_status ;;
esac
