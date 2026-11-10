# dotfiles/cmd/test.zsh — `dotfiles test`: the hermetic suite, one suite by name, or one suite
# opened with the code it tests (--edit). The suite lookup and the "what does this suite test"
# rule live here; steps/test_suites.zsh checks every suite against the same rule.

verb::define test 'the hermetic suite, one suite by name, or the suites a change touches; --edit opens a suite with its code'
verb::usage test 'test [NAME]' 'test --changed [--base REV] [--list]' 'test --for FILE.. [--list]'
verb::about test <<'EOF'
Without NAME: every tests/test_*.sh under $(help::tilde "${ARI_DOTFILES_TESTS}"),
each in a fake HOME with brew/launchctl/curl shims; nothing reaches this
machine. With NAME: the zsh plugin suite NAME.test.zsh under
$(help::tilde "${ARI_DOTFILES_ZSH_PLUGINS}") (raycast, json_sort, …) under its
OTTO_TEST__ZSH_PLUGINS_<NAME> gate (NAME upper-cased, anything not a letter
or digit as _), else the hermetic tests/test_NAME.sh (verify_show, …).
Suites run side by side, ARI_DOTFILES_TEST_JOBS at a time.

--changed and --for run only the suites the files touch: a suite itself;
the suites whose code it is (the --edit rule); the suites that name the
file's stem (steps/nix_port.zsh → every suite saying nix_port), except a
cmd/ file, which has only its test_<verb>_* suites. A file of the shared
core (lib/, tests/lib.sh, run.sh, shims, fixtures, real-tools.txt,
bin/dotfiles) runs every suite.
EOF
verb::flag test '--changed' "the files this checkout changed: against --base (default HEAD), untracked ones included"
verb::flag test '--base REV' 'with --changed: the changes since REV (origin/main covers every unpushed commit too)'
verb::flag test '--for' 'the arguments are files (absolute, or relative to the current directory), not a suite name'
verb::flag test '--list' 'with --changed or --for: print the suites and why, run nothing'
verb::section test 'Documentation rule' <<'EOF'
Every suite says what it tests: a tests/test_*.sh on line 2 ('# what it
checks'), a plugin suite on line 1 ('# Tests for <file>', a file that
exists). The test_suites step fails on one that does not.
EOF
verb::edit test test::edit '[NAME]' \
  "open NAME's suite and the code it tests in \\\$EDITOR (vi when unset), in one editor call, then run that suite and exit with its status. The code: a plugin suite's '# Tests for <file>'; steps/X.zsh for test_step_X and test_X_step; cmd/V.zsh and cmd/V/* for test_V_*. Without NAME: open tests/run.sh, run nothing. Commits nothing; exit 1 when the editor fails (nothing runs), 64 for an unknown NAME"
verb::env test ARI_DOTFILES_TESTS "the hermetic suite's directory" '$(help::tilde "${ARI_DOTFILES_TESTS}")'
verb::env test ARI_DOTFILES_ZSH_PLUGINS 'where the plugin suites (*.test.zsh) live' '$(help::tilde "${ARI_DOTFILES_ZSH_PLUGINS}")'
verb::env test ARI_DOTFILES_BLESS_GOLDEN '1 rewrites the report goldens from the renderer: ARI_DOTFILES_BLESS_GOLDEN=1 bash tests/test_report_render.sh'
verb::env test ARI_DOTFILES_TEST_JOBS 'how many suites run side by side' 'half the CPUs'

cmd_test() {
  local -A opts; local -a args
  verb::parse test "$@"
  if (( ${+opts[--changed]} || ${+opts[--for]} )); then
    (( ! ${+opts[--edit]} )) || usage_error "test: --edit opens one suite; not with --changed or --for"
    (( ${+opts[--changed]} + ${+opts[--for]} == 1 )) || usage_error "test: --changed or --for, not both"
    test::select "$@"
    return
  fi
  (( ! ${+opts[--base]} && ! ${+opts[--list]} )) || usage_error "test: --base and --list go with --changed or --for"
  (( ${#args} <= 1 )) || usage_error "test takes at most one name | args='${args[*]}'"
  (( ${+opts[--edit]} )) && { test::edit "${args[@]}"; return; }
  (( ${#args} )) || test::_exec_suite "${ARI_DOTFILES_TESTS}/run.sh"
  local REPLY
  test::resolve "${args[1]}" || usage_error "no such suite | name='${args[1]}' plugins='${ARI_DOTFILES_ZSH_PLUGINS}' tests='${ARI_DOTFILES_TESTS}'"
  test::_exec_suite "${REPLY}"
}

# test::resolve NAME: REPLY = the suite NAME names, a plugin suite first (NAME, NAME.test.zsh),
# then a hermetic one (NAME, test_NAME, test_NAME.sh); 1 when neither exists.
test::resolve() {
  local arg="${1}" name
  REPLY=""
  [[ -n "${arg}" && "${arg}" != */* && "${arg}" != .* ]] || return 1
  name="${arg%.test.zsh}"
  if [[ -f "${ARI_DOTFILES_ZSH_PLUGINS}/${name}.test.zsh" ]]; then REPLY="${ARI_DOTFILES_ZSH_PLUGINS}/${name}.test.zsh"; return 0; fi
  name="${${arg%.sh}#test_}"
  if [[ -f "${ARI_DOTFILES_TESTS}/test_${name}.sh" ]]; then REPLY="${ARI_DOTFILES_TESTS}/test_${name}.sh"; return 0; fi
  return 1
}

# The env var that ungates a plugin suite, as run_tests.zsh spells it: <name>.test.zsh →
# OTTO_TEST__ZSH_PLUGINS_<name upper-cased, non-alphanumerics as _>.
test::gate_var() {
  local name="${${1:t}%.test.zsh}"
  REPLY="OTTO_TEST__ZSH_PLUGINS_${${name:u}//[^A-Z0-9]/_}"
}

# The argv that runs SUITE: a plugin suite in zsh under its gate, a hermetic one in bash. Both
# without the ARI_DOTFILES_* this process exported (env.zsh resolves them against the real HOME:
# the Terminal plist, the state dir), so a suite sees only what it sets itself; the one variable
# meant for the suites, ARI_DOTFILES_BLESS_GOLDEN, passes.
test::_argv() {
  local suite="${1}" REPLY v
  local -a strip=()
  for v in ${(k)parameters[(I)ARI_DOTFILES_*]}; do
    [[ "${v}" == (ARI_DOTFILES_BLESS_GOLDEN|ARI_DOTFILES_TEST_JOBS) ]] || strip+=(-u "${v}")
  done
  if [[ "${suite}" == *.test.zsh ]]; then
    test::gate_var "${suite}"
    reply=(env "${strip[@]}" "${REPLY}=true" zsh "${suite}")
  else
    reply=(env "${strip[@]}" bash "${suite}")
  fi
}

test::_exec_suite() {
  local -a reply
  test::_argv "${1}"
  exec "${reply[@]}"
}

# A file of the shared core: every suite runs on it.
test::is_core() {
  local f="${1}" t="${ARI_DOTFILES_TESTS}"
  [[ "${f}" == "${ARI_DOTFILES_ROOT}/lib/"* || "${f}" == ("${t}/lib.sh"|"${t}/run.sh"|"${t}/real-tools.txt")
     || "${f}" == ("${t}/shims/"*|"${t}/fixtures/"*) || "${f}" == "${ARI_DOTFILES_CONFIG}/bin/dotfiles" ]]
}

# test::suites_for FILE..: reply = the suites the files touch, in path order; the caller's
# associative WHY maps each to the files that chose it, its array UNTESTED holds the files no suite
# covers, and CORE the core files among them (then every suite is chosen).
test::suites_for() {
  local -a all=("${ARI_DOTFILES_TESTS}"/test_*.sh(N) "${ARI_DOTFILES_ZSH_PLUGINS}"/*.test.zsh(N)) hits
  local -A code
  local f s stem REPLY
  for s in "${all[@]}"; do test::code_under "${s}"; code[${s}]=$'\n'"${(pj:\n:)reply}"$'\n'; done
  for f in "$@"; do
    if test::is_core "${f}"; then CORE+=("${f}"); continue; fi
    hits=()
    (( ${all[(Ie)${f}]} )) && hits+=("${f}")
    for s in "${all[@]}"; do [[ "${code[${s}]}" == *$'\n'"${f}"$'\n'* ]] && hits+=("${s}"); done
    stem="${${f:t}%%.*}"
    if [[ -n "${stem}" && "${f}" != "${ARI_DOTFILES_CMD}/"* ]]; then
      hits+=(${(f)"$(grep -lwF -- "${stem}" "${all[@]}" 2>/dev/null || true)"})
    fi
    hits=(${(u)hits})
    if (( ${#hits} )); then
      for s in "${hits[@]}"; do WHY[${s}]+="${WHY[${s}]:+ }${f:t}"; done
    else
      UNTESTED+=("${f}")
    fi
  done
  if (( ${#CORE} )); then
    for s in "${all[@]}"; do WHY[${s}]="core"; done
  fi
  reply=(${(ok)WHY})
}

# The files --changed or --for names, absolute: --for's arguments, or what git says this checkout
# changed against --base (default HEAD), untracked files included.
test::changed_files() {
  local base="${opts[--base]:-HEAD}" top f
  if (( ${+opts[--for]} )); then
    (( ${#args} )) || usage_error "test --for: name at least one file"
    for f in "${args[@]}"; do reply+=("${f:a}"); done
    return 0
  fi
  (( ${#args} == 0 )) || usage_error "test --changed takes no names | args='${args[*]}'"
  top="$(git -C "${ARI_DOTFILES_CONFIG}" rev-parse --show-toplevel 2>/dev/null)" \
    || usage_error "test --changed: not in a git checkout | dir='${ARI_DOTFILES_CONFIG}'"
  git -C "${top}" rev-parse --verify --quiet "${base}^{commit}" > /dev/null \
    || usage_error "test --changed: no such revision | base='${base}'"
  for f in ${(f)"$(git -C "${top}" diff --name-only "${base}" --; git -C "${top}" ls-files --others --exclude-standard)"}; do
    reply+=("${top}/${f}")
  done
  reply=(${(u)reply})
}

# --changed / --for: the suites the files touch, listed with why, then run side by side by run.sh
# (--list stops after the listing).
test::select() {
  local -A opts WHY; local -a args reply UNTESTED CORE files
  verb::parse test "$@"
  test::changed_files
  files=("${reply[@]}")
  reply=()
  (( ${#files} )) && test::suites_for "${files[@]}"
  local -a suites=("${reply[@]}") untested=("${UNTESTED[@]:t}")
  local what="${#files} changed file(s) since ${opts[--base]:-HEAD}" s
  (( ! ${+opts[--for]} )) || what="${#files} named file(s)"
  print -r -- "test: ${#suites} suite(s) for ${what}"
  if (( ${#CORE} )); then
    print -r -- "  every suite: the shared core changed | files=$(ui::paths "${CORE[@]}")"
  else
    for s in "${suites[@]}"; do print -r -- "  ${s:t}  ← ${WHY[${s}]}"; done
  fi
  if (( ${#untested} )); then
    print -r -- "  no suite covers ${#untested} file(s): ${(j:, :)untested[1,8]}${${untested[9]:+, …}:-}"
  fi
  (( ${+opts[--list]} )) && return 0
  (( ${#suites} )) || return 0
  local -a reply
  test::_argv "${ARI_DOTFILES_TESTS}/run.sh"
  exec "${reply[@]}" "${suites[@]}"
}

# test::target_path TARGET: REPLY = the file a plugin suite's '# Tests for <target>' names. A
# ~/.config path is read from this checkout's .config, another ~ path from HOME, a bare name
# from the plugins dir. Trailing punctuation (the sentence's period, comma) is not the name.
test::target_path() {
  setopt localoptions extendedglob
  local t="${1%%[.,:;]##}"
  case "${t}" in
    '~/.config/'*) REPLY="${ARI_DOTFILES_SRC_CONFIG}/${t#\~/.config/}" ;;
    '~/'*) REPLY="${HOME}/${t#\~/}" ;;
    /*) REPLY="${t}" ;;
    *) REPLY="${ARI_DOTFILES_ZSH_PLUGINS}/${t}" ;;
  esac
}

# test::plugin_target LINE1: REPLY = the target word of '# Tests for <target> …', 1 when LINE1
# does not have that shape.
test::plugin_target() {
  local line="${1}"
  REPLY=""
  [[ "${line}" == '# Tests for '[^[:space:]]* ]] || return 1
  REPLY="${${line#\# Tests for }%%[[:space:]]*}"
}

# test::code_under SUITE: reply = the files SUITE tests that exist (see the edit's help).
test::code_under() {
  setopt localoptions extendedglob
  local suite="${1}" base line REPLY verb
  reply=()
  if [[ "${suite}" == *.test.zsh ]]; then
    line=""; IFS= read -r line < "${suite}" || true
    test::plugin_target "${line}" || return 0
    test::target_path "${REPLY}"
    [[ -f "${REPLY}" ]] && reply=("${REPLY}")
    return 0
  fi
  base="${${suite:t}%.sh}"; base="${base#test_}"
  if [[ "${base}" == step_?* && -f "${ARI_DOTFILES_STEPS}/${base#step_}.zsh" ]]; then
    reply=("${ARI_DOTFILES_STEPS}/${base#step_}.zsh"); return 0
  fi
  if [[ "${base}" == ?*_step && -f "${ARI_DOTFILES_STEPS}/${base%_step}.zsh" ]]; then
    reply=("${ARI_DOTFILES_STEPS}/${base%_step}.zsh"); return 0
  fi
  verb="${base%%_*}"
  if [[ -f "${ARI_DOTFILES_CMD}/${verb}.zsh" ]]; then
    reply=("${ARI_DOTFILES_CMD}/${verb}.zsh" "${ARI_DOTFILES_CMD}/${verb}/"*(N.))
  fi
  return 0
}

# --edit [NAME]: the suite and its code in one editor call, then the suite's own exit status.
test::edit() {
  local -A opts; local -a args
  verb::parse test "$@"
  (( ${#args} <= 1 )) || usage_error "test takes at most one name | args='${args[*]}'"
  local REPLY suite
  if (( ${#args} == 0 )); then
    if ! edit::open -- "${ARI_DOTFILES_TESTS}/run.sh"; then
      log::err "editor exited non-zero | file='${ARI_DOTFILES_TESTS}/run.sh'"
      return 1
    fi
    print -r -- "next: ${CLI_NAME} test"
    return 0
  fi
  test::resolve "${args[1]}" || usage_error "no such suite | name='${args[1]}' plugins='${ARI_DOTFILES_ZSH_PLUGINS}' tests='${ARI_DOTFILES_TESTS}'"
  suite="${REPLY}"
  local -a reply
  test::code_under "${suite}"
  if ! edit::open -- "${suite}" "${reply[@]}"; then
    log::err "editor exited non-zero; nothing run | suite='${suite}'"
    return 1
  fi
  test::_argv "${suite}"
  print -r -- "test: running $(ui::paths "${suite}")"
  local -i rc=0
  "${reply[@]}" || rc=$?
  if (( rc )); then
    print -r -- "test: failed (exit ${rc}); nothing committed | suite=$(ui::paths "${suite}")"
    print -r -- "next: ${CLI_NAME} test --edit ${args[1]}"
  else
    print -r -- "test: passed; nothing committed | suite=$(ui::paths "${suite}")"
    print -r -- "next: ${CLI_NAME} test"
  fi
  return "${rc}"
}
