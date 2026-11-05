#!/usr/bin/env zsh
# Bookmarks in a published Google Doc: `[text](#bm-<slug>)` puts a bookmark on the text, `[text](#goto-<slug>)`
# links to it, and every aside marker is an implicit target for its tab's return links. Entrypoint for
# gdoc_bookmarks.py; gdoc_publish.zsh runs --check-setup, then --apply --execute, after every publish.
# The dry-run gate lives here, in lib/dry_run.zsh; the Python acts only when handed --execute.
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

# The hemingway lib holds the Docs helpers this script shares with gdoc_asides.py.
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib:${SKILLS_DIR}/ari-hemingway--lib/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
readonly PY_SCRIPT="${SCRIPT_DIR}/gdoc_bookmarks.py"

help() {
  cat <<EOF
${c_green}gdoc_bookmarks${c_rst} — check the Apps Script setup, record it, or apply a draft's bookmarks to a published Doc

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --check-setup
  zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --configure --script-id ID [--deployment-id ID] [--execute]
  zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc ID_OR_URL --file DRAFT.md [--execute]

${c_bold}Modes:${c_rst}
  --check-setup        One line per prerequisite; read-only, takes neither --execute nor --dry-run
  --configure          Record --script-id and --deployment-id in ~/.local/share/ari-hemingway/gdoc_bookmarks.json
  --apply              Bookmark --doc's #bm- runs and aside markers from --file, then relink

${c_bold}Options:${c_rst}
  --execute            --configure, --apply: write; without it the run is a dry run
  --dry-run            The default made explicit; wins over --execute and exports DRY_RUN=1
  -h, --help           Show this help

${c_bold}Environment:${c_rst}
  DRY_RUN              Set and not 0 (a parent's dry run): a dry run, --execute or not; 0 alone never acts

${c_bold}Output:${c_rst} --check-setup prints its lines and exits 1 when one is MISSING. --configure and --apply
end with one JSON line on stdout carrying "dry_run": 1 or 0; a dry run of --apply prints the plan and
the relink batch before it, and logs the exact rerun with --execute.
EOF
}

#######################################
# Whether the mode on the command line is --check-setup, the one mode that never writes.
# Arguments: the arguments handed on to the Python
#######################################
is_read_only_mode() {
  (( ${@[(Ie)--check-setup]} ))
}

main() {
  local -a py_args=()
  local execute=false dry_run_flag=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help) help; return 0 ;;
    --execute) execute=true; shift ;;
    --dry-run) dry_run_flag=true; shift ;;
    *)         py_args+=("${1}"); shift ;;
  esac; done

  if is_read_only_mode "${py_args[@]}"; then
    if [[ "${execute}" == "true" || "${dry_run_flag}" == "true" ]]; then
      log::err "--check-setup is read-only; it takes neither flag | execute='${execute}' dry_run='${dry_run_flag}'"
      return 1
    fi
    exec python3 "${PY_SCRIPT}" "${py_args[@]}"
  fi

  resolve_dry_run "${execute}" "${dry_run_flag}"
  if ! is_dry_run; then
    py_args+=(--execute)
  fi
  exec python3 "${PY_SCRIPT}" "${py_args[@]}"
}

main "${@}"
