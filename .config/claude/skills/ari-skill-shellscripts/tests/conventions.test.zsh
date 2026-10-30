#!/usr/bin/env zsh
# Conventions checks for every skill's zsh scripts: behaviour tests that prove the rules in a throwaway
# zsh (quoted subscripts, grep and early-exiting consumers under pipefail, arithmetic under errexit),
# then a lint over every skill's scripts for the same shapes. Run after any update to this skill or to
# any skill's scripts: zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh

set -euo pipefail
setopt extendedglob

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly SELF="${0:A}"   # inside a function $0 is the function's name; the lint skips this file by this path
# An identifier, `[`, then a quote: `m["${id}"]=…` or `${m['k']}`. Shell tests (`[[ `, `[ -f`), array
# indexes (`$a[1]`) and regex classes (`[^"]`) all have something other than a quote right after `[`.
readonly QUOTED_SUBSCRIPT='[A-Za-z_][A-Za-z0-9_]*\[["'"'"']'
# A grep stage followed by another pipe on the same line (`||` is masked first).
readonly GREP_NON_FINAL='(^|[ ;|(])grep( [^|]*)?\|'
# A consumer that may stop before its producer is done: SIGPIPE 141 under pipefail.
readonly EARLY_EXIT_CONSUMER='\|[[:space:]]*(head( |$)|grep -m|sed [^|]*([ ;{'"'"'"]q)([ ;}'"'"'"]|$)|awk [^|]*[^a-z_]exit([^a-z_]|$))'
readonly LINT_OK_MARK='# lint: ok'
readonly FIXTURE_MARK='# expect '

typeset -gi PASS=0 FAIL=0 WARN=0

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local -a missing
  local cmd
  for cmd in awk mktemp seq; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Reporting ---

#######################################
# Record one check and print its line.
# Globals: PASS, FAIL, WARN (incremented)
# Arguments: $1 - PASS|FAIL|WARN; $2 - where (file:line or a test name); $3 - what
#######################################
report() {
  local verdict="${1}" where="${2}" what="${3}"
  case "${verdict}" in
    PASS) (( PASS += 1 )) ;;
    FAIL) (( FAIL += 1 )) ;;
    WARN) (( WARN += 1 )) ;;
  esac
  print -r -- "${verdict}  ${where}  ${what}"
}

#######################################
# Run a snippet in a fresh zsh and compare its exit code with the one the rule predicts.
# Globals: None
# Arguments: $1 - test name; $2 - "zero"|"nonzero"; $3 - the snippet
#######################################
expect_rc() {
  local name="${1}" want="${2}" snippet="${3}"
  local rc=0
  zsh -c "${snippet}" >/dev/null 2>&1 || rc=$?
  if [[ "${want}" == zero && "${rc}" -eq 0 ]] || [[ "${want}" == nonzero && "${rc}" -ne 0 ]]; then
    report PASS "behaviour:${name}" "exit ${rc} as the rule predicts (${want})"
    return 0
  fi
  report FAIL "behaviour:${name}" "exit ${rc}, the rule predicts ${want} | snippet='${snippet}'"
}

# --- Behaviour tests: the rules, executable ---

#######################################
# Prove each rule in a throwaway zsh, so the why is runnable.
# Globals: None
# Arguments: None
#######################################
behaviour_tests() {
  log::info "Behaviour tests: the rules in a throwaway zsh"
  # Rule: never quotes inside an associative-array subscript.
  expect_rc quoted-subscript-read-dies-under-set-u nonzero \
    'set -u; typeset -A m; id=k; m["${id}"]=v; print -- "${m[${id}]}"'
  expect_rc quoted-subscript-stores-the-quotes nonzero \
    'typeset -A m; m["k"]=v; [[ "${(k)m}" == k ]]'
  expect_rc unquoted-subscript-reads-back zero \
    'set -u; typeset -A m; id=k; m[$id]=v; [[ "${m[$id]}" == v && "${m[${id}]}" == v ]]'
  # Rule: under pipefail, grep with no match fails the pipeline.
  expect_rc grep-no-match-fails-pipeline nonzero \
    'set -o pipefail; echo x | grep y | cat'
  expect_rc awk-filter-passes-on-no-match zero \
    'set -o pipefail; echo x | awk "/y/" | cat'
  expect_rc grep-or-true-wrapped-passes-on-no-match zero \
    'set -o pipefail; { echo x | grep y || true; } | cat'
  expect_rc grep-c-or-true-passes-on-no-match zero \
    'set -eo pipefail; n=$(printf "" | grep -c . || true); [[ "${n}" == 0 ]]'
  expect_rc grep-c-in-substitution-dies-under-set-e nonzero \
    'set -e; n=$(printf "" | grep -c .); print -- "${n}"'
  # Rule: a consumer that stops early kills a long producer with SIGPIPE under pipefail.
  expect_rc head-of-long-producer-fails-under-pipefail nonzero \
    'set -o pipefail; seq 1 400000 | head -1 >/dev/null'
  expect_rc awk-exit-of-long-producer-fails-under-pipefail nonzero \
    'set -o pipefail; seq 1 400000 | awk "/^1\$/ { print; exit }" >/dev/null'
  expect_rc latching-awk-reads-to-eof-and-passes zero \
    'set -o pipefail; seq 1 400000 | awk "!found && /^1\$/ { print; found=1 }" >/dev/null'
  # Rule: arithmetic that evaluates to 0 ends a set -e script.
  expect_rc post-increment-from-zero-dies-under-set-e nonzero \
    'set -e; n=0; (( n++ )); print ok'
  expect_rc plus-equals-passes-under-set-e zero \
    'set -e; n=0; (( n += 1 )); [[ "${n}" == 1 ]]'
}

# --- Lint ---

#######################################
# Whether a file is a zsh script: a .zsh name or a zsh shebang on line 1.
# Globals: None
# Arguments: $1 - path
#######################################
is_zsh_script() {
  local file="${1}" first=""
  [[ -f "${file}" ]] || return 1
  [[ "${file}" == *.zsh ]] && return 0
  IFS= read -r first < "${file}" || true
  [[ "${first}" == '#!'*zsh* ]]
}

#######################################
# Every zsh script under one skill directory: bin/*, lib/*.zsh, tests/*.zsh, lessons/**/*.zsh.
# Globals: None
# Arguments: $1 - the skill directory (symlinks resolved by the caller)
#######################################
scripts_of() {
  local dir="${1}" file
  for file in "${dir}"/bin/*(N.) "${dir}"/lib/*.zsh(N.) "${dir}"/tests/*.zsh(N.) "${dir}"/lessons/**/*.zsh(N.); do
    is_zsh_script "${file}" && print -r -- "${file}"
  done
  return 0
}

#######################################
# The shell-level code of one line: a trailing ` #…` comment removed, then every single-quoted word
# (preceded by start, space, `=`, `(` or `{`) removed, so awk, jq and python programs do not count.
# A quote right after `[` stays, since that is the subscript shape itself.
# Globals: None
# Arguments: $1 - the line
#######################################
shell_code_of() {
  local line=" ${1}"
  line="${line%% \#*}"
  line="${line//(#b)([ =({])\'[^\']#\'/${match[1]}}"
  print -r -- "${line}"
}

#######################################
# Lint one file: FAIL per quoted subscript; WARN per grep stage that is not last, and per early-exiting
# consumer, in a file that sets pipefail. Heredoc bodies, single-quoted multi-line programs, comment
# lines and lines ending in `# lint: ok` are skipped.
# Globals: QUOTED_SUBSCRIPT, GREP_NON_FINAL, EARLY_EXIT_CONSUMER, LINT_OK_MARK
# Arguments: $1 - path; $2 - how to print it
#######################################
lint_file() {
  local file="${1}" shown="${2}" line code masked heredoc_end="" quotes
  local -i n=0 has_pipefail=0 in_embedded=0
  grep -q 'pipefail' "${file}" 2>/dev/null && has_pipefail=1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( n += 1 ))
    if [[ -n "${heredoc_end}" ]]; then   # a heredoc body (Python, JSON, help text) is not zsh
      [[ "${line//[[:space:]]/}" == "${heredoc_end}" ]] && heredoc_end=""
      continue
    fi
    quotes="${line//[^\']/}"
    if (( in_embedded )); then          # inside `python3 -c '…`: a line with an odd quote count closes it
      (( ${#quotes} % 2 )) && in_embedded=0
      continue
    fi
    [[ "${line}" =~ '^[[:space:]]*#' ]] && continue
    [[ "${line}" == *"${LINT_OK_MARK}" ]] && continue
    if [[ "${line}" =~ "<<-?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?[[:space:]]*$" ]]; then
      heredoc_end="${match[1]}"         # the opener's own line is still shell: lint it below
    fi
    if [[ "${line}" =~ "(python3?|node|perl|ruby) (-[a-zA-Z]+ )*-[ce] '" ]] && (( ${#quotes} % 2 )); then
      in_embedded=1
      continue
    fi
    code="${line%% \#*}"                 # trailing comment off; quoted programs stay, for the pipeline checks
    if [[ "$(shell_code_of "${line}")" =~ ${QUOTED_SUBSCRIPT} ]]; then
      report FAIL "${shown}:${n}" "quotes inside an associative-array subscript: ${MATCH}… (write name[\$key] or \${name[\${key}]}, never name[\"\${key}\"] or name['k'])"
    fi
    (( has_pipefail )) || continue
    [[ "${code}" == *nopipefail* ]] && continue
    masked="${code//\|\|/ OR }"
    if [[ "${masked}" =~ ${GREP_NON_FINAL} && "${code}" != *'|| true; }'* ]]; then
      report WARN "${shown}:${n}" "grep is not the last pipeline stage under pipefail; no match exits 1 (use awk, or { grep … || true; } |)"
    fi
    if [[ "${masked}" =~ ${EARLY_EXIT_CONSUMER} ]]; then
      report WARN "${shown}:${n}" "a consumer that may stop early (head, grep -m, sed q, awk exit) under pipefail; a long producer dies of SIGPIPE 141 (latch and read to EOF, or nopipefail for this pipeline)"
    fi
  done < "${file}"
}

#######################################
# Lint every zsh script of every skill under a root; FAIL when none was found.
# Globals: SELF
# Arguments: $1 - the skills root
#######################################
lint_skills() {
  local root="${1}" skill real file
  local -i files=0
  log::info "Lint: every skill's zsh scripts | root='${root}'"
  for skill in "${root}"/*(N); do
    real="${skill:A}"
    [[ -d "${real}" ]] || continue
    for file in "${(@f)$(scripts_of "${real}")}"; do
      [[ -n "${file}" ]] || continue
      [[ "${file:A}" == "${SELF}" ]] && continue   # this file holds the bad shapes on purpose (snippets, fixtures)
      (( files += 1 ))
      lint_file "${file}" "${root}/${skill:t}/${file#${real}/}"
    done
  done
  if (( files == 0 )); then
    report FAIL "lint" "no zsh scripts found under ${root}"
    return 0
  fi
  report PASS "lint" "scanned ${files} zsh scripts under ${root}"
}

#######################################
# Prove the lint on a fixture: every line marked `# expect FAIL` or `# expect WARN` must be reported with
# that verdict, and no other line may be. The markers are trailing comments, so the lint never sees them.
# Globals: FIXTURE_MARK
# Arguments: None
#######################################
lint_self_test() {
  log::info "Lint self-test on fixtures"
  local root fixture
  root="$(mktemp -d)"
  trap 'rm -rf "${root}"' EXIT
  mkdir -p "${root}/fixture/bin"
  fixture="${root}/fixture/bin/cases.zsh"
  cat > "${fixture}" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
typeset -A files_of
files_of["${id}"]="x"                                   # expect FAIL
print -- "${files_of['k']}"                             # expect FAIL
files_of[$id]="x"
print -- "${files_of[${id}]}"
[[ -f "${file}" ]] && echo ok
[ -f "$x" ] && echo ok
print -- "${array[1]}" "$array[2]"
[[ "${line}" =~ '[^"]+' ]] && echo regex
awk 'BEGIN { m["x"] = 1 }' </dev/null
jq '.x["k"]' <<<'{}'
# files_of["${id}"] in a comment is fine
files_of["${id}"]="reviewed"   # lint: ok
printf '%s\n' a | grep a | cat                          # expect WARN
printf '%s\n' a | grep -c a | cat                       # expect WARN
printf '%s\n' a | grep a || true | cat                  # expect WARN
{ printf '%s\n' a | grep a || true; } | cat
printf '%s\n' a | grep -q a || true
printf '%s\n' a | grep a
seq 1 3 | head -1                                       # expect WARN
seq 1 3 | grep -m1 2                                    # expect WARN
seq 1 3 | sed -n '1p;q'                                 # expect WARN
seq 1 3 | awk '/2/ { print; exit }'                     # expect WARN
seq 1 3 | awk '!found && /2/ { print; found=1 }'
setopt localoptions nopipefail; seq 1 3 | head -1
python3 - <<'PY'
print(os.environ["HOME"], task["Progress"])
PY
python3 -c '
import os
print(os.environ["HOME"])' "${arg}"
cat <<EOF2
help text with files_of["x"] is a heredoc body
EOF2
files_of["${id}"]="after the embedded blocks"           # expect FAIL
EOF
  local -A want
  local -i n=0
  local line
  while IFS= read -r line; do
    (( n += 1 ))
    [[ "${line}" == *"${FIXTURE_MARK}"* ]] && want[$n]="${line##*${FIXTURE_MARK}}"
  done < "${fixture}"
  local out
  out="$(PASS=0 FAIL=0 WARN=0; lint_skills "${root}" 2>/dev/null | awk '/^(FAIL|WARN)  /')"
  local -A got
  local verdict where
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    verdict="${line%%  *}"; where="${${line#*  }%%  *}"
    got[${where##*:}]="${verdict}"
  done <<<"${out}"
  local -i ok=1
  local k
  for k in "${(@k)want}"; do
    [[ "${got[$k]:-}" == "${want[$k]}" ]] || { ok=0; report FAIL "lint-self-test:line-${k}" "want ${want[$k]}, got ${got[$k]:-nothing}"; }
  done
  for k in "${(@k)got}"; do
    [[ -n "${want[$k]:-}" ]] || { ok=0; report FAIL "lint-self-test:line-${k}" "unexpected ${got[$k]}: $(sed -n "${k}p" "${fixture}")"; }
  done
  (( ok )) && report PASS "lint-self-test" "${#want} marked lines reported as marked, every other line silent"
  rm -rf "${root}"; trap - EXIT
}

# --- Help ---

help() {
  cat <<EOF
${c_green}conventions.test.zsh${c_rst} — prove the shell conventions in a throwaway zsh, then lint every skill's zsh scripts for them

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh [OPTIONS]

${c_bold}Options:${c_rst}
  --behaviour-only  Run only the throwaway-zsh behaviour tests and the lint self-test
  --lint-only       Run only the lint self-test and the lint over the skills
  --root DIR        Skills root to lint (default: ${SKILLS_DIR})
  -h, --help        Show this help

${c_bold}Output:${c_rst}
  One line per check, then a summary. FAIL: a rule broken for certain (a quoted associative-array subscript);
  the run exits 1. WARN: a heuristic match under pipefail (grep not last, or head / grep -m / sed q / awk exit
  on a pipeline), to read and fix or mark; never fails the run. A reviewed line ends in \`# lint: ok\`.
EOF
}

# --- Main ---

main() {
  # === PARSE ===
  local behaviour=true lint=true root="${SKILLS_DIR}"
  while (( $# > 0 )); do case "${1}" in
    -h|--help)        help; return 0 ;;
    --behaviour-only) lint=false; shift ;;
    --lint-only)      behaviour=false; shift ;;
    --root)           root="${2:?--root requires a value}"; shift 2 ;;
    -*)               log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  check_prerequisites || return 1

  # === MASSAGE ===
  root="${root:A}"

  # === VALIDATE ===
  if [[ ! -d "${root}" ]]; then
    log::err "Skills root is not a directory | root='${root}'"
    return 1
  fi

  # === LOGIC ===
  [[ "${behaviour}" == true ]] && behaviour_tests
  lint_self_test
  [[ "${lint}" == true ]] && lint_skills "${root}"

  print -r -- "summary  pass=${PASS} fail=${FAIL} warn=${WARN}"
  if (( FAIL > 0 )); then
    log::err "Checks failed | fail='${FAIL}' pass='${PASS}' warn='${WARN}'"
    return 1
  fi
  log::info "All checks passed | pass='${PASS}' warn='${WARN}'"
}

main "${@}"
