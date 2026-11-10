#!/usr/bin/env zsh
# Delete one calendar event through concert-mcp (apps/concert-mcp of the homelab checkout): `concert-mcp del`.
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
${c_green}cal-del.zsh${c_rst} — delete one event from Ari's Concerts or Personal calendar through concert-mcp (\`concert-mcp del\`)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-del.zsh --title T [--date YYYY-MM-DD] [--pick N] [--dry-run | --execute]

${c_bold}Options:${c_rst}
  ${c_cyan}--execute${c_rst}   delete the event; without it the run is concert-mcp's own --dry-run
  ${c_cyan}--dry-run${c_rst}   the default, said explicitly; wins over --execute
  ${c_cyan}-h, --help${c_rst}  show this help; the fields: \`uv run --project <concert-mcp> concert-mcp del --help\`
  Every other flag, and a JSON object as the argument or on stdin, passes to concert-mcp unchanged.

${c_bold}Output:${c_rst}
  stdout: concert-mcp's reply: a unique match deleted, a numbered list when several match (rerun with
  --pick N), or "nothing deleted". \`FIX:\` / \`NO_REPLY\` / \`NOT SENT\` as for cal-add.zsh.
EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    return 0
  fi
  concert_mcp::run "${SCRIPT_PATH}" del -- "${@}"
}

main "$@"
