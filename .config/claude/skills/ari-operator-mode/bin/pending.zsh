#!/usr/bin/env zsh
# pending.zsh — the row Claude typed onto Ari's prompt and he has not yet entered or cleared, kept on
# disk per Claude session (lib/marker.zsh) so a compaction cannot lose it: frontier.zsh reads it as the
# default --pending and names that line as his row (row_pending, row_running), never as text he must
# clear. Brief sets it right after run.zsh prints TYPED:; Proceed clears it when he says entered or
# cleared, or when a capture finds the prompt idle without it (pending_seen false).
# Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/pending.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SCRIPT_DIR:h}/lib/marker.zsh"

# --- Constants ---

readonly ACTIONS=(set clear show)
readonly EXIT_NONE=3

help() {
  cat <<HELP
${c_green}pending.zsh${c_rst} — record, clear or show the row typed onto Ari's prompt for this Claude session

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/pending.zsh set --text TEXT
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/pending.zsh clear
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/pending.zsh show

${c_bold}Options:${c_rst}
  --text TEXT    with set: the text after run.zsh's TYPED: prefix, verbatim (it starts with run_log ')
  --session ID   the Claude session (default: \$CLAUDE_CODE_SESSION_ID)
  --root DIR     where the marker lives (default: /tmp); the marker is DIR/operator-mode/PENDING-<session>
  -h, --help     this help

${c_bold}Output:${c_rst} pending=<text> after set and show; pending= after clear or when nothing is recorded.
${c_bold}Exit codes:${c_rst} 0 done, or shown; ${EXIT_NONE} nothing recorded (show only); 1 a bad call.
  set and clear are idempotent: set overwrites, a second clear is a no-op.
HELP
}

# --- Parse ---

action='' text='' session="${CLAUDE_CODE_SESSION_ID:-}" root_dir='/tmp'
while (( $# > 0 )); do
  case "${1}" in
    set|clear|show) action="${1}"; shift ;;
    --text) text="${2:?--text requires a value}"; shift 2 ;;
    --session) session="${2:?--session requires a value}"; shift 2 ;;
    --root) root_dir="${2:?--root requires a value}"; shift 2 ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown argument | arg='${1}' actions='${(j:, :)ACTIONS}'"; help; exit 1 ;;
  esac
done

# --- Validate ---

if [[ -z "${action}" ]]; then log::err "An action is required | actions='${(j:, :)ACTIONS}'"; help; exit 1; fi
if [[ -z "${session}" ]]; then log::err "No session: set CLAUDE_CODE_SESSION_ID or pass --session"; exit 1; fi
if [[ "${action}" == set && -z "${text}" ]]; then log::err "set needs the typed text | flag='--text'"; help; exit 1; fi
if [[ "${action}" == set && "${text}" == "TYPED: "* ]]; then
  log::err "The text is what follows TYPED:, without the prefix | text='${text}'"
  exit 1
fi

readonly MARKER="$(marker_path "${root_dir}" PENDING "${session}")"

# --- Logic ---

pending_set() {
  marker_set "${MARKER}" "${text}"
  log::info "Pending row recorded | session='${session}' marker='${MARKER}'"
  print -r -- "pending=${text}"
}

pending_clear() {
  if marker_clear "${MARKER}"; then
    log::info "Pending row cleared | session='${session}'"
  else
    log::info "No pending row to clear | session='${session}'"
  fi
  print -r -- "pending="
}

pending_show() {
  local recorded
  if recorded="$(marker_show "${MARKER}")"; then
    print -r -- "pending=${recorded}"
    return 0
  fi
  print -r -- "pending="
  return "${EXIT_NONE}"
}

case "${action}" in
  set) pending_set ;;
  clear) pending_clear ;;
  show) pending_show ;;
esac
