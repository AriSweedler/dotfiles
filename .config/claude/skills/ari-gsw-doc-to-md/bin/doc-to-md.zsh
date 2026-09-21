#!/usr/bin/env zsh
# Thin entrypoint: checks prerequisites, then runs doc_to_md.py under a wall-clock cap.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

# Put the shared python logging lib on PYTHONPATH so doc_to_md.py imports it bare.
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1

readonly CONVERTER="${SCRIPT_DIR}/doc_to_md.py"
readonly TIMEOUT_S=120

help() {
  cat <<EOF
${c_green}doc-to-md${c_rst} — convert a Google Doc to markdown (readable, or publish-ready with --publish)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh <doc-url-or-id> [options]
  zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh --json-file PATH [options]

${c_bold}Options:${c_rst}
  --tab ID          Render one tab by id (overrides any ?tab= in the URL)
  --out PATH        Write markdown to PATH (default: <title-slug>.md in CWD)
  --stdout          Print markdown to stdout instead of writing a file
  --force           Overwrite the output file if it already exists
  --publish         Emit the /ari-hemingway--format-gdoc dialect: Doc title first,
                    Drive URLs raw, linked images via mermaid.ink (for share-gdoc)
  --json-file PATH  Convert a saved Docs JSON instead of fetching
  -h, --help        Show this help
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
    log::err "no arguments | usage='zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh <doc-url-or-id>'"
    help
    exit 1
  fi

  check_prerequisites

  log::info "converting | arg1='${1}'"
  local exit_code=0
  local err_file
  err_file="$(mktemp)"
  run_with_timeout "${TIMEOUT_S}" "${err_file}" python3 "${CONVERTER}" "${@}" || exit_code=$?
  cat "${err_file}" >&2
  rm -f "${err_file}"
  if (( exit_code == 124 )); then
    log::err "converter timed out | timeout_s='${TIMEOUT_S}'"
  fi
  return "${exit_code}"
}

main "${@}"
