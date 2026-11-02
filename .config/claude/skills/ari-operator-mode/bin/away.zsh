#!/usr/bin/env zsh
# away.zsh — the absence Ari announced (the host itself going away: the laptop taken, closed, off its
# network), kept on disk per Claude session (lib/marker.zsh) so a compaction cannot lose it: frontier.zsh
# reads it as the default --away, so a host_unreachable or read_timed_out cut-off renders as the away
# line, never as his P0. Set when he says the host will be unreachable; cleared when he says he is back,
# or by frontier.zsh when a capture reaches the host. Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/away.zsh --help

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
readonly MAX_WORDS=12

help() {
  cat <<HELP
${c_green}away.zsh${c_rst} — record, clear or show the absence Ari announced for this Claude session

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/away.zsh set --text TEXT
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/away.zsh clear
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/away.zsh show

${c_bold}Options:${c_rst}
  --text TEXT    with set: the clause of his message that says the host goes away, under ${MAX_WORDS} words, on one
                 line, with no question mark or backtick (the away line quotes it and has exactly one question mark)
  --session ID   the Claude session (default: \$CLAUDE_CODE_SESSION_ID)
  --root DIR     where the marker lives (default: /tmp); the marker is DIR/operator-mode/AWAY-<session>
  -h, --help     this help

${c_bold}Output:${c_rst} away=<text> after set and show; away= after clear or when nothing is recorded.
${c_bold}Exit codes:${c_rst} 0 done, or shown; ${EXIT_NONE} nothing recorded (show only); 1 a bad call.
  set and clear are idempotent: set overwrites, a second clear is a no-op.
HELP
}

# --- Parse ---

action='' text='' session="${CLAUDE_CODE_SESSION_ID:-}" root_dir='/tmp'
while (( $# > 0 )); do
  case "${1}" in
    set|clear|show) action="${1}"; shift ;;
    --text) text="${2-}"; shift 2 ;;
    --session) session="${2:?--session requires a value}"; shift 2 ;;
    --root) root_dir="${2:?--root requires a value}"; shift 2 ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown argument | arg='${1}' actions='${(j:, :)ACTIONS}'"; help; exit 1 ;;
  esac
done

# --- Validate ---

if [[ -z "${action}" ]]; then log::err "An action is required | actions='${(j:, :)ACTIONS}'"; help; exit 1; fi
if [[ -z "${session}" ]]; then log::err "No session: set CLAUDE_CODE_SESSION_ID or pass --session"; exit 1; fi
if [[ "${action}" == set ]]; then
  if [[ -z "${text}" ]]; then log::err "set needs his words | flag='--text'"; help; exit 1; fi
  if [[ "${text}" == *[$'\n?`']* ]]; then
    log::err "His words go on one line with no question mark or backtick: the away line quotes them | text='${text}'"
    exit 1
  fi
  if (( ${#${=text}} > MAX_WORDS )); then
    log::err "His words are the clause about leaving, not the whole message | words='${#${=text}}' max_words='${MAX_WORDS}'"
    exit 1
  fi
fi

readonly MARKER="$(marker_path "${root_dir}" AWAY "${session}")"

# --- Logic ---

away_set() {
  marker_set "${MARKER}" "${text}"
  log::info "Absence recorded | session='${session}' marker='${MARKER}'"
  print -r -- "away=${text}"
}

away_clear() {
  if marker_clear "${MARKER}"; then
    log::info "Absence cleared | session='${session}'"
  else
    log::info "No absence to clear | session='${session}'"
  fi
  print -r -- "away="
}

away_show() {
  local recorded
  if recorded="$(marker_show "${MARKER}")"; then
    print -r -- "away=${recorded}"
    return 0
  fi
  print -r -- "away="
  return "${EXIT_NONE}"
}

case "${action}" in
  set) away_set ;;
  clear) away_clear ;;
  show) away_show ;;
esac
