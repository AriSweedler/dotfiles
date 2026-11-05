#!/usr/bin/env zsh
# Conventions checks for every skill's zsh scripts: behaviour tests that prove the rules in a throwaway
# zsh (quoted subscripts, grep and early-exiting consumers under pipefail, arithmetic under errexit, the
# dry-run default of lib/dry_run.zsh and bin/example), then a lint over every skill's scripts for the
# same shapes. Run after any update to this skill or to any skill's scripts:
# zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh

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
# Case arms, matched only in arm position (`  --x)`, `-n|--x)`, `"--x")`), so a `--dry-run` passed to
# another tool or written in a string is not an arm. A bin/ script with a `--dry-run` arm or a
# `run_mut` call mutates: it must also have an `--execute` arm and call resolve_dry_run.
readonly ARM_HEAD='^[[:space:]]*\(?([^)]*\|)?["'"'"']?'
readonly ARM_TAIL='["'"'"']?[)|]'
readonly MUTATING_ARM="${ARM_HEAD}--dry-run(=\\*)?${ARM_TAIL}"
readonly OTHER_ACT_ARM="${ARM_HEAD}--(apply|yes|confirm|no-dry-run)${ARM_TAIL}"
readonly EXECUTE_ARM="${ARM_HEAD}--execute${ARM_TAIL}"
readonly RUN_MUT_CALL='(^|[[:space:];&|({])run_mut[[:space:]]'
readonly RESOLVE_CALL='(^|[[:space:];&|({])resolve_dry_run[[:space:]]'
# A second gate: a local definition of a lib/dry_run.zsh function, or DRY_RUN as true/false.
readonly GATE_DEFINITION='^[[:space:]]*(function[[:space:]]+)?(run_mut|is_dry_run|resolve_dry_run|write_mut|report_dry_run)[[:space:]]*\(\)'
readonly DRY_RUN_BOOL='(^|[^A-Za-z0-9_])DRY_RUN\}?"?[[:space:]]*(==?|!=)[[:space:]]*["'"'"']?(true|false)([^A-Za-z0-9_]|$)'
# A redirect or a pipe on a run_mut line acts outside run_mut, so it writes even in a dry run.
readonly MUT_REDIRECT='((^|[^0-9&<>])>>?[[:space:]]*[^&[:space:]]|\|[[:space:]]*run_mut[[:space:]])'
readonly DRY_RUN_LIB_TAIL='ari-skill-shellscripts/lib/dry_run.zsh'
readonly LINT_OK_MARK='# lint: ok'
readonly FIXTURE_MARK='# expect '

typeset -gi PASS=0 FAIL=0 WARN=0
typeset -ga LINT_ONLY_SKILLS=()   # --skill NAME (repeatable); empty = every skill

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

#######################################
# Prove the dry-run default: lib/dry_run.zsh's decision and run_mut, then bin/example as the template
# a mutating script copies. Each snippet starts with DRY_RUN unset unless it sets one.
# Globals: SKILLS_DIR
# Arguments: None
#######################################
dry_run_tests() {
  log::info "Behaviour tests: a mutating script is a dry run unless --execute"
  local d
  d="$(mktemp -d)"
  local libs='unset DRY_RUN; source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"; source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/dry_run.zsh";'
  # Rule: no flag is a dry run; only --execute acts; dry run wins however it is asked for.
  expect_rc no-flag-is-a-dry-run zero "${libs}"' resolve_dry_run false false; [[ "${DRY_RUN}" == 1 ]]'
  expect_rc execute-alone-acts zero "${libs}"' resolve_dry_run true false; [[ "${DRY_RUN}" == 0 ]]'
  expect_rc dry-run-flag-sets-dry-run zero "${libs}"' resolve_dry_run false true; [[ "${DRY_RUN}" == 1 ]]'
  expect_rc dry-run-beats-execute zero "${libs}"' resolve_dry_run true true; [[ "${DRY_RUN}" == 1 ]]'
  expect_rc inherited-dry-run-beats-execute zero "${libs}"' export DRY_RUN=1; resolve_dry_run true false; [[ "${DRY_RUN}" == 1 ]]'
  expect_rc inherited-zero-alone-never-acts zero "${libs}"' export DRY_RUN=0; resolve_dry_run false false; [[ "${DRY_RUN}" == 1 ]]'
  expect_rc child-inherits-the-dry-run zero "${libs}"' resolve_dry_run false false; [[ "$(printenv DRY_RUN)" == 1 ]]'
  # Rule: every mutation goes through run_mut, which only logs unless the run resolved to act.
  expect_rc run-mut-changes-nothing-in-a-dry-run zero "${libs} f='${d}/a';"' resolve_dry_run false false; run_mut touch "${f}"; [[ ! -e "${f}" ]]'
  expect_rc run-mut-changes-nothing-unresolved zero "${libs} f='${d}/b';"' run_mut touch "${f}"; [[ ! -e "${f}" ]]'
  expect_rc run-mut-acts-on-execute zero "${libs} f='${d}/c';"' resolve_dry_run true false; run_mut touch "${f}"; [[ -e "${f}" ]]'
  expect_rc inherited-zero-unresolved-never-acts zero "${libs} f='${d}/d';"' export DRY_RUN=0; run_mut touch "${f}" 2>/dev/null; [[ ! -e "${f}" ]]'
  expect_rc run-mut-keeps-argument-boundaries zero "${libs}"' resolve_dry_run false false; [[ "$(run_mut gh pr create --title "a b" 2>&1)" == *"--title '"'"'a b'"'"'"* ]]'
  expect_rc run-mut-dry-out-stands-in zero "${libs}"' resolve_dry_run false false; [[ "$(run_mut --dry-out "<url>" gh pr create 2>/dev/null)" == "<url>" ]]'
  # Rule: a write goes through write_mut; a redirect on run_mut truncates even in a dry run.
  expect_rc redirect-on-run-mut-truncates-in-a-dry-run nonzero "${libs} f='${d}/r1'; print keep > \"\${f}\";"' resolve_dry_run false false; run_mut print new > "${f}"; [[ "$(<"${f}")" == keep ]]'
  expect_rc write-mut-keeps-the-file-in-a-dry-run zero "${libs} f='${d}/r2'; print keep > \"\${f}\";"' resolve_dry_run false false; print new | write_mut "${f}"; [[ "$(<"${f}")" == keep ]]'
  expect_rc write-mut-writes-on-execute zero "${libs} f='${d}/r3';"' resolve_dry_run true false; print new | write_mut "${f}"; [[ "$(<"${f}")" == new ]]'
  expect_rc write-mut-drains-a-long-producer zero "${libs} f='${d}/r4';"' set -o pipefail; resolve_dry_run false false; seq 1 400000 | write_mut "${f}"'
  # Rule: one gate; never a read-only or second DRY_RUN.
  expect_rc readonly-dry-run-is-refused nonzero "${libs}"' readonly DRY_RUN=1; resolve_dry_run true false'
  expect_rc lib-refuses-over-a-local-run-mut nonzero 'source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"; run_mut() { :; }; source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/dry_run.zsh"'
  expect_rc report-names-the-exact-rerun zero "${libs}"' resolve_dry_run false true; run_mut touch x; [[ "$(report_dry_run "${HOME}/.claude/skills/s/bin/x" --out "a b" --dry-run 2>&1)" == *"rerun='"'"'zsh \$HOME/.claude/skills/s/bin/x --out '"'"'a b'"'"' --execute'"'"'"* ]]'
  # The template: bin/example copies a file into --out-dir only under --execute, and exits 0 either way.
  local ex="zsh '${SKILLS_DIR}/ari-skill-shellscripts/bin/example' --mode registry --target ari-skill-shellscripts --out-dir"
  expect_rc example-second-execute-changes-nothing zero "unset DRY_RUN; ${ex} '${d}/e6' --execute >/dev/null 2>&1 && [[ \"\$(${ex} '${d}/e6' --execute 2>/dev/null)\" == *changes=0 ]]"
  expect_rc example-out-dir-needs-a-target nonzero "unset DRY_RUN; zsh '${SKILLS_DIR}/ari-skill-shellscripts/bin/example' --mode registry --out-dir '${d}/e7' --execute"
  expect_rc example-default-changes-nothing zero "unset DRY_RUN; ${ex} '${d}/e1' >/dev/null 2>&1 && [[ ! -e '${d}/e1' ]]"
  expect_rc example-execute-acts zero "unset DRY_RUN; ${ex} '${d}/e2' --execute >/dev/null 2>&1 && [[ -e '${d}/e2/ari-skill-shellscripts.SKILL.md' ]]"
  expect_rc example-dry-run-after-execute-wins zero "unset DRY_RUN; ${ex} '${d}/e3' --execute --dry-run >/dev/null 2>&1 && [[ ! -e '${d}/e3' ]]"
  expect_rc example-dry-run-before-execute-wins zero "unset DRY_RUN; ${ex} '${d}/e4' --dry-run --execute >/dev/null 2>&1 && [[ ! -e '${d}/e4' ]]"
  expect_rc example-inherited-dry-run-beats-execute zero "export DRY_RUN=1; ${ex} '${d}/e5' --execute >/dev/null 2>&1 && [[ ! -e '${d}/e5' ]]"
  rm -rf "${d}"
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
# The end-of-file verdict on a bin/ script that mutates: FAIL with no `--execute` arm (its default
# acts), else FAIL with no resolve_dry_run call (an inherited DRY_RUN, or nothing, decides).
# Globals: None
# Arguments: $1 - where; $2 - what made it mutating; $3 - has an --execute arm (0|1); $4 - calls resolve_dry_run (0|1)
#######################################
report_mutation_gate() {
  local where="${1}" how="${2}" has_execute="${3}" has_resolve="${4}"
  if (( ! has_execute )); then
    report FAIL "${where}" "mutates (${how}) but has no --execute arm, so its default acts (add --execute and --dry-run arms and call resolve_dry_run from lib/dry_run.zsh; a script that writes only its own investigation folder drops --dry-run instead)"
    return 0
  fi
  if (( ! has_resolve )); then
    report FAIL "${where}" "mutates (${how}) but never calls resolve_dry_run, so the flags do not decide (source lib/dry_run.zsh; call resolve_dry_run right after the parse loop)"
  fi
}

#######################################
# Lint one file. FAIL per quoted subscript; per local definition of a lib/dry_run.zsh function; per
# DRY_RUN compared with or set to true/false; per redirect or pipe on a run_mut line. In a bin/ file
# that mutates (a `--dry-run` arm or a `run_mut` call), FAIL once with no `--execute` arm or no
# resolve_dry_run call. WARN per `--apply`/`--yes`/`--confirm`/`--no-dry-run` arm, and, in a file that
# sets pipefail, per grep stage that is not last and per early-exiting consumer. Heredoc bodies,
# single-quoted multi-line programs, comment lines and lines ending in `# lint: ok` are skipped.
# Globals: the regex constants above, DRY_RUN_LIB_TAIL, LINT_OK_MARK
# Arguments: $1 - path; $2 - how to print it
#######################################
lint_file() {
  local file="${1}" shown="${2}" line code masked heredoc_end="" quotes mutates_how="" shell_code
  local -i n=0 has_pipefail=0 in_embedded=0 mutates_at=0 has_execute=0 has_resolve=0 is_gate_lib=0
  [[ "${file:A}" == *"/${DRY_RUN_LIB_TAIL}" ]] && is_gate_lib=1
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
    shell_code="$(shell_code_of "${line}")"
    if [[ "${shell_code}" =~ ${QUOTED_SUBSCRIPT} ]]; then
      report FAIL "${shown}:${n}" "quotes inside an associative-array subscript: ${MATCH}… (write name[\$key] or \${name[\${key}]}, never name[\"\${key}\"] or name['k'])"
    fi
    if (( ! is_gate_lib )) && [[ "${code}" =~ ${GATE_DEFINITION} ]]; then
      report FAIL "${shown}:${n}" "defines ${match[2]}(), a second dry-run gate (source lib/dry_run.zsh and delete the local copy)"
    fi
    if [[ "${shell_code}" =~ ${DRY_RUN_BOOL} ]]; then
      report FAIL "${shown}:${n}" "DRY_RUN as true/false; it is 1 or 0, and a script reads it only through is_dry_run (lib/dry_run.zsh)"
    fi
    if [[ "${shell_code}" =~ ${RUN_MUT_CALL} && "${${shell_code//[0-9]#>[[:space:]]#\/dev\/null/}//\|\|/ OR }" =~ ${MUT_REDIRECT} ]]; then
      report FAIL "${shown}:${n}" "a redirect or pipe on a run_mut line acts outside run_mut, so it writes even in a dry run (pipe the content into write_mut instead)"
    fi
    if [[ "${code}" =~ ${OTHER_ACT_ARM} ]]; then
      report WARN "${shown}:${n}" "an act flag other than --execute (rename it to --execute and update every documented invocation)"
    fi
    [[ "${code}" =~ ${EXECUTE_ARM} ]] && has_execute=1
    [[ "${shell_code}" =~ ${RESOLVE_CALL} ]] && has_resolve=1
    if (( mutates_at == 0 )) && [[ "${code}" =~ ${MUTATING_ARM} || "${shell_code}" =~ ${RUN_MUT_CALL} ]]; then
      mutates_at="${n}"; mutates_how="${${MATCH##[[:space:]|(;&{\"\']#}%[[:space:])|\"\']}"
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
  if (( mutates_at > 0 )) && [[ "${shown}" != */lib/* ]]; then   # a lib's caller owns the flags
    report_mutation_gate "${shown}:${mutates_at}" "${mutates_how}" "${has_execute}" "${has_resolve}"
  fi
}

#######################################
# Lint every zsh script of every skill under a root (only the --skill ones, when given); FAIL when
# none was found.
# Globals: SELF, LINT_ONLY_SKILLS
# Arguments: $1 - the skills root
#######################################
lint_skills() {
  local root="${1}" skill real file
  local -i files=0
  log::info "Lint: zsh scripts | root='${root}' skills='${(j:, :)LINT_ONLY_SKILLS:-every}'"
  for skill in "${root}"/*(N); do
    real="${skill:A}"
    [[ -d "${real}" ]] || continue
    (( ${#LINT_ONLY_SKILLS} == 0 || ${LINT_ONLY_SKILLS[(Ie)${skill:t}]} )) || continue
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
# Prove the lint on fixtures: every line marked `# expect FAIL` or `# expect WARN` must be reported with
# that verdict, and no other line of any fixture may be. The markers are trailing comments, so the lint
# never sees them.
# Globals: FIXTURE_MARK
# Arguments: None
#######################################
lint_self_test() {
  log::info "Lint self-test on fixtures"
  local root bin
  root="$(mktemp -d)"
  trap 'rm -rf "${root}"' EXIT
  bin="${root}/fixture/bin"
  mkdir -p "${bin}"
  cat > "${bin}/acts_by_default.zsh" <<'EOF'
#!/usr/bin/env zsh
dry_run=false
while (( $# > 0 )); do case "${1}" in
  --dry-run) dry_run=true; shift ;;                     # expect FAIL
  *) shift ;;
esac; done
EOF
  cat > "${bin}/quoted_arm.zsh" <<'EOF'
#!/usr/bin/env zsh
log::info "pass --execute) to act is a string, not an arm"
case "${1}" in
  "--dry-run") dry_run=true ;;                          # expect FAIL
esac
EOF
  cat > "${bin}/apply_flag.zsh" <<'EOF'
#!/usr/bin/env zsh
while (( $# > 0 )); do case "${1}" in
  -a|--apply) apply=true; shift ;;                      # expect WARN
esac; done
EOF
  cat > "${bin}/run_mut_only.zsh" <<'EOF'
#!/usr/bin/env zsh
run_mut gh pr create --fill                             # expect FAIL
run_mut touch x
EOF
  cat > "${bin}/no_resolve.zsh" <<'EOF'
#!/usr/bin/env zsh
while (( $# > 0 )); do case "${1}" in
  --execute) execute=true; shift ;;
  --dry-run=*) dry_run=true; shift ;;                   # expect FAIL
esac; done
EOF
  cat > "${bin}/second_gate.zsh" <<'EOF'
#!/usr/bin/env zsh
run_mut() { print -r -- "$*"; }                         # expect FAIL
[[ "${DRY_RUN}" == "true" ]] && echo dry                # expect FAIL
typeset DRY_RUN="false"                                 # expect FAIL
EOF
  cat > "${bin}/conforming.zsh" <<'EOF'
#!/usr/bin/env zsh
local -a probe=(git push --dry-run)
while (( $# > 0 )); do case "${1}" in
  --execute) execute=true; shift ;;
  -n|--dry-run) dry_run=true; shift ;;
esac; done
resolve_dry_run "${execute}" "${dry_run}"
run_mut touch x
run_mut gh api -X POST repos/o/r/labels 2>/dev/null >/dev/null
run_mut jq . in.json > out.json                         # expect FAIL
seq 1 3 | run_mut tee out.txt                           # expect FAIL
print -r -- "${body}" | write_mut out.txt
[[ -d x ]] || run_mut mkdir -p x
is_dry_run && echo previewing
EOF
  mkdir -p "${root}/fixture/lib"
  cat > "${root}/fixture/lib/wraps_run_mut.zsh" <<'EOF'
#!/usr/bin/env zsh
publish() { run_mut gh release create "${1}"; }
EOF
  cat > "${bin}/cases.zsh" <<'EOF'
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
  --dry-run)  in help text is not an arm
EOF2
run_cmd kubectl apply --dry-run=client -f x
print -- "--dry-run) inside a string is not an arm"
files_of["${id}"]="after the embedded blocks"           # expect FAIL
EOF
  local -A want
  local -i n
  local line fixture
  for fixture in "${bin}"/*.zsh; do
    n=0
    while IFS= read -r line; do
      (( n += 1 ))
      [[ "${line}" == *"${FIXTURE_MARK}"* ]] && want[${fixture:t}:${n}]="${line##*${FIXTURE_MARK}}"
    done < "${fixture}"
  done
  local out
  out="$(PASS=0 FAIL=0 WARN=0; LINT_ONLY_SKILLS=(); lint_skills "${root}" 2>/dev/null | awk '/^(FAIL|WARN)  /')"
  local -A got
  local verdict where
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    verdict="${line%%  *}"; where="${${line#*  }%%  *}"
    got[${where:t}]="${verdict}"
  done <<<"${out}"
  local -i ok=1
  local k
  for k in "${(@k)want}"; do
    [[ "${got[$k]:-}" == "${want[$k]}" ]] || { ok=0; report FAIL "lint-self-test:${k}" "want ${want[$k]}, got ${got[$k]:-nothing}"; }
  done
  for k in "${(@k)got}"; do
    [[ -n "${want[$k]:-}" ]] || { ok=0; report FAIL "lint-self-test:${k}" "unexpected ${got[$k]}: $(awk -v n="${k##*:}" 'NR == n' "${bin}/${k%%:*}")"; }
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
  --behaviour-only  Run only the throwaway-zsh behaviour tests (dry-run gate included) and the lint self-test
  --lint-only       Run only the lint self-test and the lint over the skills
  --root DIR        Skills root to lint (default: ${SKILLS_DIR})
  --skill NAME      Lint only this skill's scripts (repeatable; default: every skill)
  -h, --help        Show this help

${c_bold}Output:${c_rst}
  One line per check (\`FAIL  <file>:<line>  <what and the fix>\`), then \`summary  pass=N fail=N warn=N\`.
  FAIL exits 1; WARN never does. The catalog of both is /ari-skill-shellscripts § Validation.
  A reviewed line ends in \`# lint: ok\`.
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
    --skill)          LINT_ONLY_SKILLS+=("${2:?--skill requires a value}"); shift 2 ;;
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
  local skill
  for skill in "${LINT_ONLY_SKILLS[@]}"; do
    if [[ ! -d "${root}/${skill}" ]]; then
      log::err "No such skill under the root | skill='${skill}' root='${root}'"
      return 1
    fi
  done

  # === LOGIC ===
  if [[ "${behaviour}" == true ]]; then
    behaviour_tests
    dry_run_tests
  fi
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
