# dotfiles/cmd/test.zsh — `dotfiles test`: the hermetic suite, one suite by name, or one suite
# opened with the code it tests (--edit). The suite lookup and the "what does this suite test"
# rule live here; steps/test_suites.zsh checks every suite against the same rule.

help_test() {
  cat <<EOF
the hermetic suite, or one suite by name; --edit opens a suite with its code

${c_bold}Usage${c_rst}
  ${DF} test [NAME]
  ${DF} test --edit [NAME]

  Without NAME: every tests/test_*.sh under $(help::tilde "${ARI_DOTFILES_TESTS}"),
  each in a fake HOME with brew/launchctl/curl shims; nothing reaches this
  machine. With NAME: the zsh plugin suite NAME.test.zsh under
  $(help::tilde "${ARI_DOTFILES_ZSH_PLUGINS}") (raycast, json_sort, …) under its
  OTTO_TEST__ZSH_PLUGINS_<NAME> gate (NAME upper-cased, anything not a letter
  or digit as _), else the hermetic tests/test_NAME.sh (verify_show, …).

  Every suite says what it tests: a tests/test_*.sh on line 2 ('# what it
  checks'), a plugin suite on line 1 ('# Tests for <file>', a file that
  exists). The test_suites step fails on one that does not.

${c_bold}Flags${c_rst}
  --edit   open NAME's suite and the code it tests in \$EDITOR (vi when unset),
           in one editor call, then run that suite and exit with its status.
           The code: a plugin suite's '# Tests for <file>'; steps/X.zsh for
           test_step_X and test_X_step; cmd/V.zsh and cmd/V/* for test_V_*.
           Without NAME: open tests/run.sh, run nothing. Commits nothing;
           exit 1 when the editor fails (nothing runs), 64 for an unknown NAME

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_TESTS)
      the hermetic suite's directory
      (default $(help::tilde "${ARI_DOTFILES_TESTS}"))
  $(ENV ARI_DOTFILES_ZSH_PLUGINS)
      where the plugin suites (*.test.zsh) live
      (default $(help::tilde "${ARI_DOTFILES_ZSH_PLUGINS}"))
  $(ENV ARI_DOTFILES_BLESS_GOLDEN)
      1 rewrites the report goldens from the renderer:
      ARI_DOTFILES_BLESS_GOLDEN=1 bash tests/test_report_render.sh
EOF
}

cmd_test() {
  local -a edit=()
  zparseopts -D -E -F -K -- -edit=edit || usage_error "test: bad flags | args='$*'"
  (( $# <= 1 )) || usage_error "test takes at most one name | args='$*'"
  if (( ${#edit} )); then
    test::edit "$@"
    return
  fi
  if (( $# == 0 )); then
    test::_exec_suite "${ARI_DOTFILES_TESTS}/run.sh"
  fi
  local REPLY
  test::resolve "${1}" || usage_error "no such suite | name='${1}' plugins='${ARI_DOTFILES_ZSH_PLUGINS}' tests='${ARI_DOTFILES_TESTS}'"
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
    [[ "${v}" == ARI_DOTFILES_BLESS_GOLDEN ]] || strip+=(-u "${v}")
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

# test::target_path TARGET: REPLY = the file a plugin suite's '# Tests for <target>' names. A
# ~/.config path is read from this checkout's .config, another ~ path from HOME, a bare name
# from the plugins dir. Trailing punctuation (the sentence's period, comma) is not the name.
test::target_path() {
  setopt localoptions extendedglob
  local t="${1%%[.,:;]##}"
  case "${t}" in
    '~/.config/'*) REPLY="${ARI_DOTFILES_CONFIG}/${t#\~/.config/}" ;;
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

# test::code_under SUITE: reply = the files SUITE tests that exist (see help_test's --edit).
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
  local editor="${EDITOR:-vi}" REPLY suite
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  if (( $# == 0 )); then
    if ! ${=editor} "${ARI_DOTFILES_TESTS}/run.sh"; then
      log::err "editor exited non-zero | editor='${editor}' file='${ARI_DOTFILES_TESTS}/run.sh'"
      return 1
    fi
    print -r -- "next: ${CLI_NAME} test"
    return 0
  fi
  test::resolve "${1}" || usage_error "no such suite | name='${1}' plugins='${ARI_DOTFILES_ZSH_PLUGINS}' tests='${ARI_DOTFILES_TESTS}'"
  suite="${REPLY}"
  local -a reply
  test::code_under "${suite}"
  local -a files=("${suite}" "${reply[@]}")
  if ! ${=editor} "${files[@]}"; then
    log::err "editor exited non-zero; nothing run | editor='${editor}' suite='${suite}'"
    return 1
  fi
  test::_argv "${suite}"
  print -r -- "test: running $(ui::paths "${suite}")"
  local -i rc=0
  "${reply[@]}" || rc=$?
  if (( rc )); then
    print -r -- "test: failed (exit ${rc}); nothing committed | suite=$(ui::paths "${suite}")"
    print -r -- "next: ${CLI_NAME} test --edit ${1}"
  else
    print -r -- "test: passed; nothing committed | suite=$(ui::paths "${suite}")"
    print -r -- "next: ${CLI_NAME} test"
  fi
  return "${rc}"
}
