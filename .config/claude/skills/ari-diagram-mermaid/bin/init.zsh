#!/usr/bin/env zsh
# Set up a ari-diagram-mermaid session: create a fresh temp folder and print the
# path to write the .mmd source to. Replaces the brittle manual mktemp + date
# step (BSD `date` has no %3N).

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${SCRIPT_DIR:h:h}"  # <skill>/bin → skills root

# --- Logging (source the canonical lib — never re-define log::* inline) ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Investigation folder helper ---

readonly LIB_INVESTIGATION="${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
if [[ ! -r "${LIB_INVESTIGATION}" ]]; then
  log::err "Missing investigation-folder lib | path='${LIB_INVESTIGATION}'"
  exit 1
fi
source "${LIB_INVESTIGATION}"

# --- Help ---

help() {
  cat <<EOF
${c_green}init${c_rst} — create a temp folder for a mermaid diagram and print where to write it

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-diagram-mermaid/bin/init.zsh [--name NAME]

${c_bold}Options:${c_rst}
  --name NAME   Basename for the .mmd file (default: diagram)
  -h, --help    Show this help

${c_bold}Output (key=value on stdout):${c_rst}
  diagram_dir   The created temp directory
  diagram_file  The .mmd path to write the diagram source to, then pass to bake
EOF
}

# --- Main ---

main() {
  # === PARSE ===
  local name="diagram"

  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --name)     name="${2:?--name requires a value}"; shift 2 ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===

  name="${name%.mmd}"

  # === VALIDATE ===

  [[ -n "${name}" ]] || { log::err "Empty --name after stripping .mmd"; return 1; }

  # === LOGIC ===

  local diagram_dir diagram_file
  diagram_dir="$(mk_investigation_dir /tmp ari-diagram-mermaid)"
  diagram_file="${diagram_dir}/${name}.mmd"

  log::info "Mermaid session ready | diagram_dir='${diagram_dir}' diagram_file='${diagram_file}'"

  cat <<EOF
diagram_dir=${diagram_dir}
diagram_file=${diagram_file}
EOF
}

main "${@}"
