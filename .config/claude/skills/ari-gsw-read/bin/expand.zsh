#!/usr/bin/env zsh
# Thin entrypoint: checks prerequisites, then runs expand_links.py under a wall-clock cap.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${SCRIPT_DIR:h:h}"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

# Put the shared python logging lib on PYTHONPATH so expand_links.py imports it bare.
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"

readonly EXPANDER="${SCRIPT_DIR}/expand_links.py"
# Folders fan out to one gws fetch per doc, so allow more headroom than a single-doc tool.
readonly TIMEOUT_S=600
readonly WORK_DIR="/tmp/ari-gsw-read"
readonly OUT_DIR="${WORK_DIR}/out"
readonly LINKS_FILE="${WORK_DIR}/links.txt"

help() {
  cat <<EOF
${c_green}expand${c_rst} — expand a Drive folder or Google Doc into per-tab doc links

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-gsw-read/bin/expand.zsh <folder-or-doc-url-or-id>

${c_bold}Output:${c_rst}
  One tab-level doc URL per line (.../document/d/<id>/edit?tab=<tabId>), written
  to ${LINKS_FILE} and echoed on stdout. Also creates ${OUT_DIR} for the
  converter step — no setup commands needed before or after this call.
  A folder expands to every Google Doc inside (non-recursive) × every tab;
  a doc expands to every tab. Feed each line to /ari-gsw-doc-to-md.

${c_bold}Options:${c_rst}
  -h, --help  Show this help
EOF
}

check_prerequisites() {
  local -a missing=()
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  command -v gws >/dev/null 2>&1 || missing+=("gws")
  (( ${#missing} == 0 )) && return
  log::err "missing prerequisites | missing='${(j:, :)missing}'"
  exit 1
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    return 0
  fi
  if (( $# < 1 )); then
    log::err "no arguments | usage='zsh $HOME/.claude/skills/ari-gsw-read/bin/expand.zsh <folder-or-doc-url-or-id>'"
    help
    exit 1
  fi

  check_prerequisites
  mkdir -p "${OUT_DIR}"

  log::info "expanding | arg1='${1}'"
  local exit_code=0
  local err_file
  err_file="$(mktemp)"
  # -u keeps stdout unbuffered and tee records it, so a timeout still leaves the
  # per-doc links emitted so far in ${LINKS_FILE}.
  run_with_timeout "${TIMEOUT_S}" "${err_file}" python3 -u "${EXPANDER}" "${@}" | tee "${LINKS_FILE}" || exit_code=$?
  cat "${err_file}" >&2
  rm -f "${err_file}"
  if (( exit_code == 124 )); then
    log::err "expander timed out | timeout_s='${TIMEOUT_S}'"
  fi
  log::info "links recorded | links_file='${LINKS_FILE}' count='$(wc -l < "${LINKS_FILE}" | tr -d ' ')'"
  return "${exit_code}"
}

main "${@}"
