# step test_suites — every test suite says what it tests: a hermetic tests/test_*.sh on line 2
# ('# what it checks', under the shebang), a zsh plugin suite on line 1 ('# Tests for <file>', a
# file that exists). One that does not fails the step, by hand only, naming
# `dotfiles test --edit NAME`. A plugin with no suite at all is counted, not failed.
# No apply: the fix is writing the line.
step::declare test_suites --group repo --needs dotfiles_repo \
  --desc "every test suite (tests/test_*.sh, zsh/plugins/*.test.zsh) says what it tests on its first lines"
step::watches test_suites '.config/dotfiles/tests/**' '.config/zsh/plugins/**'

check::test_suites() {
  need_lib "${ARI_DOTFILES_CMD}/test.zsh" || return 3
  local tests="${ARI_DOTFILES_TESTS}" plugins="${ARI_DOTFILES_ZSH_PLUGINS}"
  # A suite's target is a plugin or a ~/.config/bin script: a new or removed one changes a dir.
  local -a CACHE_EXTRA=("${ARI_DOTFILES_CMD}/test.zsh")
  cache::check step::test_suites::live "${tests}" "${tests}"/test_*.sh(N) \
    "${plugins}" "${plugins}"/*.zsh(N) "${ARI_DOTFILES_CONFIG}/bin"
}

step::test_suites::live() {
  local tests="${ARI_DOTFILES_TESTS}" plugins="${ARI_DOTFILES_ZSH_PLUGINS}" f l1 l2 name target REPLY
  local -a problems=() fixes=()
  local -i hermetic=0 suites=0 bare=0
  for f in "${tests}"/test_*.sh(N.); do
    hermetic+=1
    l1="" l2=""
    { IFS= read -r l1; IFS= read -r l2; } < "${f}" || true
    [[ "${l2}" == '# '[^[:space:]]* ]] && continue
    name="${${f:t}%.sh}"; name="${name#test_}"
    [[ -f "${plugins}/${name}.test.zsh" ]] && name="test_${name}"
    problems+=("tests/${f:t}: line 2 is not a '# ' line saying what it checks")
    fixes+=("${name}")
  done
  for f in "${plugins}"/*.test.zsh(N.); do
    suites+=1
    l1=""
    IFS= read -r l1 < "${f}" || true
    name="${${f:t}%.test.zsh}"
    if ! test::plugin_target "${l1}"; then
      problems+=("zsh/plugins/${f:t}: line 1 is not '# Tests for <file>'")
      fixes+=("${name}")
      continue
    fi
    target="${REPLY}"
    test::target_path "${target}"
    if [[ ! -f "${REPLY}" ]]; then
      problems+=("zsh/plugins/${f:t}: '# Tests for ${target}' names no file (${REPLY})")
      fixes+=("${name}")
    fi
  done
  for f in "${plugins}"/*.zsh(N.); do
    [[ "${f}" == *.test.zsh || "${f:t}" == run_tests.zsh ]] && continue
    [[ -f "${f%.zsh}.test.zsh" ]] || bare+=1
  done
  if (( ${#problems} )); then
    verdict fail undocumented -m -d "${(j:; :)problems}" -f "${CLI_NAME} test --edit ${fixes[1]}"
    return 0
  fi
  verdict ok documented -d "${hermetic} hermetic and ${suites} plugin suites say what they test; ${bare} plugins have no suite"
}
