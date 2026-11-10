#!/usr/bin/env zsh
# Add one calendar event through concert-mcp (apps/concert-mcp of the homelab checkout): `concert-mcp add --concert`.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
source "${SCRIPT_DIR:h}/lib/concert_mcp.zsh"

readonly SCRIPT_PATH="${0:a}"

help() {
  cat <<EOF
${c_green}cal-add.zsh${c_rst} — add one event to Ari's calendar through concert-mcp (\`concert-mcp add --concert\`)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-add.zsh [--title T --start S --location L ...] [--dry-run | --execute]
  zsh $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-add.zsh --execute < event.json

${c_bold}Options:${c_rst}
  ${c_cyan}--execute${c_rst}   insert the event; without it the run is concert-mcp's own --dry-run
  ${c_cyan}--dry-run${c_rst}   the default, said explicitly; wins over --execute
  ${c_cyan}-h, --help${c_rst}  show this help; the event fields: \`uv run --project <concert-mcp> concert-mcp add --help\`
  Every other flag, and a JSON object as the argument or on stdin, passes to concert-mcp unchanged.

${c_bold}Output:${c_rst}
  stdout: concert-mcp's reply. \`FIX: <why>\`: the input was wrong. \`NO_REPLY\`: the reply was delivered to the
  live chat. Otherwise the reply text, ending in \`NOT SENT: <why>\` when no chat was live.
EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    return 0
  fi
  concert_mcp::run "${SCRIPT_PATH}" add --concert -- "${@}"
}

main "$@"
