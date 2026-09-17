#!/usr/bin/env zsh
# Feed every case in tests/mention_matcher_cases.json through the three whole-word matchers
# (jq lib/check_definitions_order.jq, JS mentionRe in workflows/definitions_refine.js, Python
# mention_re in bin/cluster_definitions.py) and fail on any disagreement or wrong expectation.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly SKILL_DIR="${SCRIPT_DIR:h}"
readonly DEFAULT_CASES="${SCRIPT_DIR}/mention_matcher_cases.json"
readonly JQ_SOURCE="${SKILL_DIR}/lib/check_definitions_order.jq"
readonly JS_SOURCE="${SKILL_DIR}/workflows/definitions_refine.js"
readonly PY_DIR="${SKILL_DIR}/bin"
readonly PY_LIB="${SKILLS_DIR}/ari-skill-pythonscripts/lib"

# --- Prerequisites ---

#######################################
# Check that the binaries and the three matcher sources are present.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local cmd
  local missing=()
  for cmd in jq node python3; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  for f in "${JQ_SOURCE}" "${JS_SOURCE}" "${PY_DIR}/cluster_definitions.py"; do
    [[ -f "${f}" ]] || missing+=("${f}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands or files | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Matchers: each prints one true/false line per case, in order ---

#######################################
# Run the jq matcher: the lib's `def` lines plus a test expression over the cases.
# Globals: JQ_SOURCE
# Arguments: $1 - cases file
#######################################
run_jq() {
  local cases="${1}"
  local defs
  defs="$(awk '/^def /' "${JQ_SOURCE}")"
  jq -r "${defs} .[] | . as \$c | (\$c.text | test(\$c.term | mention_re; \"i\"))" "${cases}"
}

#######################################
# Run the JS matcher: the norm/escapeRe/mentionRe lines from the refine workflow, verbatim.
# Globals: JS_SOURCE
# Arguments: $1 - cases file
#######################################
run_js() {
  local cases="${1}"
  local defs
  defs="$(awk '/^const (norm|escapeRe|mentionRe) = /' "${JS_SOURCE}")"
  node -e "${defs}
const cases = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))
for (const c of cases) console.log(String(mentionRe(c.term).test(c.text)))" "${cases}"
}

#######################################
# Run the Python matcher via the module the cluster script ships.
# Globals: PY_DIR, PY_LIB
# Arguments: $1 - cases file
#######################################
run_py() {
  local cases="${1}"
  PYTHONPATH="${PY_LIB}:${PY_DIR}" PYTHONDONTWRITEBYTECODE=1 python3 -c '
import json, sys
import cluster_definitions as cd
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    print(str(bool(cd.mention_re(c["term"]).search(c["text"]))).lower())' "${cases}"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}check_mention_matchers${c_rst} — the jq, JS and Python whole-word matchers must agree on every case

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/tests/check_mention_matchers.zsh [--cases FILE]

${c_bold}Options:${c_rst}
  --cases FILE  Cases JSON: [{term, text, expect}] (default: tests/mention_matcher_cases.json)
  -h, --help    Show this help

${c_bold}Output:${c_rst} one line per disagreement on stdout; "OK: N cases" when all agree. Exit 1 on any failure.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local cases="${DEFAULT_CASES}"
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --cases)    cases="${2:?--cases requires a value}"; shift 2 ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === VALIDATE ===
  [[ -f "${cases}" ]] || { log::err "Cases file not found | cases='${cases}'"; return 1; }

  # === LOGIC ===
  local -a terms texts expected got_jq got_js got_py
  terms=("${(@f)$(jq -r '.[].term' "${cases}")}")
  texts=("${(@f)$(jq -r '.[].text' "${cases}")}")
  expected=("${(@f)$(jq -r '.[].expect' "${cases}")}")
  got_jq=("${(@f)$(run_jq "${cases}")}")
  got_js=("${(@f)$(run_js "${cases}")}")
  got_py=("${(@f)$(run_py "${cases}")}")

  local n="${#terms}" failures=0 i
  for (( i = 1; i <= n; i++ )); do
    if [[ "${got_jq[i]}" != "${expected[i]}" || "${got_js[i]}" != "${expected[i]}" || "${got_py[i]}" != "${expected[i]}" ]]; then
      failures=$(( failures + 1 ))
      echo "MISMATCH term='${terms[i]}' text='${texts[i]}' expect=${expected[i]} jq=${got_jq[i]} js=${got_js[i]} py=${got_py[i]}"
    fi
  done
  if (( failures > 0 )); then
    log::err "Matchers disagree | cases='${n}' failures='${failures}'"
    return 1
  fi
  log::ok "Matchers agree | cases='${n}'"
  echo "OK: ${n} cases"
}

main "${@}"
