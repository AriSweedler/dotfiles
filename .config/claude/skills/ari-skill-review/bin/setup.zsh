#!/usr/bin/env zsh
# Scaffold a skill-review investigation folder and print its path to stdout.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly LIB_INVDIR="${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
if [[ ! -r "${LIB_INVDIR}" ]]; then
  print -u2 "[ERROR] missing investigation_folder lib | path='${LIB_INVDIR}'"
  exit 1
fi
source "${LIB_INVDIR}"

readonly REVIEW_ROOT="/tmp/skill-review"
# One file per SKILL.md § Reviewer panel entry, plus spec-questions.md. findings.md
# is left out: the harness refuses a subagent's Write to it, so only the main
# thread creates it, and its absence marks a subagent run.
readonly -a SCAFFOLD_FILES=(
  structure.md
  clarity.md
  edge-case.md
  reuse.md
  interaction.md
  examples.md
  kernighan-ritchie.md
  deflake.md
  spec-questions.md
)

help() {
  cat <<EOF
${c_green}setup${c_rst} — scaffold a skill-review investigation folder

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-skill-review/bin/setup.zsh --skill NAME

${c_bold}Output:${c_rst}
  Prints the created folder path to stdout. Creates these empty files:
  ${(j:, :)SCAFFOLD_FILES}

${c_bold}Options:${c_rst}
  --skill NAME  Name of the skill being reviewed (required)
  -h, --help    Show this help
EOF
}

main() {
  local skill=""
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help)
        help
        return 0
        ;;
      --skill)
        skill="${2:?--skill requires a value}"
        shift 2
        ;;
      *)
        log::err "unknown flag | flag='${1}'"
        help
        exit 1
        ;;
    esac
  done

  if [[ -z "${skill}" ]]; then
    log::err "missing required flag | flag='--skill'"
    help
    exit 1
  fi

  local folder
  folder="$(mk_investigation_dir "${REVIEW_ROOT}" "${skill}")"
  local file
  for file in "${SCAFFOLD_FILES[@]}"; do
    : >| "${folder}/${file}"
  done
  log::info "created review folder | skill='${skill}' folder='${folder}' count='${#SCAFFOLD_FILES}' files='${(j:, :)SCAFFOLD_FILES}'"
  print -- "${folder}"
}

main "${@}"
