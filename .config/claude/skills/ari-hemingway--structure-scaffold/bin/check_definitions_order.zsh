#!/usr/bin/env zsh
# Mechanical check for a scaffold definitions table: every table term a definition mentions
# must be an earlier row (whole-word, incl. plural/-ed/-ing), no self-mention, sentence and
# word caps, no vague filler. Read-only; exits non-zero on any violation.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly CHECK_JQ="${SCRIPT_DIR:h}/lib/check_definitions_order.jq"

# --- Constants ---

readonly DEFAULT_MAX_SENTENCES=2
readonly DEFAULT_MAX_WORDS=25

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Prerequisites ---

#######################################
# Check that required binaries and the jq program are present.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  [[ -f "${CHECK_JQ}" ]] || missing+=("${CHECK_JQ}")
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands or files | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Help ---

help() {
  cat <<EOH
${c_green}check_definitions_order${c_rst} — verify a definitions table reads top to bottom with no forward references

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file ROWS.json [OPTIONS]

${c_bold}Options:${c_rst}
  --file ROWS.json       JSON array of {term, definition} in table order, or an object with .rows / .ordered (required)
  --max-sentences N      Sentences allowed per definition (default ${DEFAULT_MAX_SENTENCES})
  --max-words N          Words allowed per sentence (default ${DEFAULT_MAX_WORDS})
  -h, --help             Show this help

${c_bold}Output:${c_rst} one violation per line on stdout; "OK: N rows" when clean. Exit 1 on any violation.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local file="" max_sentences="${DEFAULT_MAX_SENTENCES}" max_words="${DEFAULT_MAX_WORDS}"
  while (( $# > 0 )); do case "${1}" in
    -h|--help)        help; return 0 ;;
    --file)           file="${2:?--file requires a value}"; shift 2 ;;
    --max-sentences)  max_sentences="${2:?--max-sentences requires a value}"; shift 2 ;;
    --max-words)      max_words="${2:?--max-words requires a value}"; shift 2 ;;
    -*)               log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === VALIDATE ===
  [[ -n "${file}" ]] || { log::err "Missing --file"; help; return 1; }
  [[ -f "${file}" ]] || { log::err "Rows file not found | file='${file}'"; return 1; }
  [[ "${max_sentences}" == <-> && "${max_words}" == <-> ]] || {
    log::err "Caps must be integers | max_sentences='${max_sentences}' max_words='${max_words}'"; return 1; }

  # === LOGIC ===
  local n_rows violations
  n_rows="$(jq '(if type == "object" then (.rows // .ordered) else . end) | length' "${file}")"
  violations="$(jq -r --argjson max_sentences "${max_sentences}" --argjson max_words "${max_words}" -f "${CHECK_JQ}" "${file}")"
  if [[ -z "${violations}" ]]; then
    log::ok "Definitions table is linear | rows='${n_rows}' max_sentences='${max_sentences}' max_words='${max_words}'"
    echo "OK: ${n_rows} rows"
    return 0
  fi
  local n_violations
  n_violations="$(print -r -- "${violations}" | wc -l | tr -d ' ')"
  log::err "Definitions table has violations | rows='${n_rows}' violations='${n_violations}'"
  print -r -- "${violations}"
  return 1
}

main "${@}"
