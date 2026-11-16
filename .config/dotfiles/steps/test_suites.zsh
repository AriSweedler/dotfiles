# step test_suites — every test suite says what it tests: a hermetic tests/test_*.sh on line 2
# ('# what it checks', under the shebang), a zsh plugin suite on line 1 ('# Tests for <file>', a
# file that exists). One that does not fails the step, by hand only, naming
# `dotfiles test --edit NAME`. A plugin with no suite at all is counted, not failed.
# And a closed gap stays closed: every line of tests/suites.manifest names a unit the test audit
# (docs/test-audit.md) said needs a suite and the suite that now covers it; a unit whose suite is gone
# fails the step, and so does a line whose unit is gone (the line goes with it). The audit's rows still
# marked `needs a suite` are counted, not failed.
# No apply: the fix is writing the line or the suite.
step::declare test_suites --group repo --needs dotfiles_repo \
  --desc "every test suite (tests/test_*.sh, zsh/plugins/*.test.zsh) says what it tests on its first lines"
step::watches test_suites '.config/dotfiles/tests/**' '.config/zsh/plugins/**'

check::test_suites() {
  need_lib "${ARI_DOTFILES_CMD}/test.zsh" || return 3
  local tests="${ARI_DOTFILES_TESTS}" plugins="${ARI_DOTFILES_ZSH_PLUGINS}"
  # A suite's target is a plugin or a ~/.config/bin script: a new or removed one changes a dir.
  local -a CACHE_EXTRA=("${ARI_DOTFILES_CMD}/test.zsh")
  local manifest="${ARI_DOTFILES_SUITES_MANIFEST:-${tests}/suites.manifest}" root="${ARI_DOTFILES_SUITES_ROOT:-${ARI_DOTFILES_SRC_CONFIG:h}}"
  local -a listed=()
  [[ -r "${manifest}" ]] && listed=( ${(f)"$(awk '!/^#/ && NF >= 2 { print $1; print $2 }' "${manifest}")"} )
  cache::check step::test_suites::live "${tests}" "${tests}"/test_*.sh(N) \
    "${plugins}" "${plugins}"/*.zsh(N) "${ARI_DOTFILES_SRC_CONFIG}/bin" \
    "${manifest}" "${ARI_DOTFILES_SRC}/docs/test-audit.md" "${root}/${^listed[@]}"
}

#######################################
# The manifest's broken promises, one problem per line into reply: a unit whose suite is gone, a line
# whose unit is gone, a line that is not "unit suite". Paths are relative to the shared repo root.
# Globals: ARI_DOTFILES_SUITES_MANIFEST, ARI_DOTFILES_SUITES_ROOT (seams for the tests)
#######################################
step::test_suites::manifest() {
  local manifest="${ARI_DOTFILES_SUITES_MANIFEST:-${ARI_DOTFILES_TESTS}/suites.manifest}" root="${ARI_DOTFILES_SUITES_ROOT:-${ARI_DOTFILES_SRC_CONFIG:h}}"
  local line unit suite extra
  reply=()
  [[ -r "${manifest}" ]] || return 0   # no manifest, nothing promised
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    read -r unit suite extra <<< "${line}"
    if [[ -z "${suite}" || -n "${extra}" ]]; then reply+=("suites.manifest: '${line}' is not 'unit suite'"); continue; fi
    if [[ ! -e "${root}/${unit}" ]]; then reply+=("suites.manifest: ${unit} is gone; remove its line"); continue; fi
    [[ -f "${root}/${suite}" ]] || reply+=("${unit} lost its suite ${suite} (suites.manifest)")
  done < "${manifest}"
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
  step::test_suites::manifest
  if (( ${#reply} )); then
    verdict fail suite-lost -m -d "${(j:; :)reply}" -f "restore the suite, or edit ${ARI_DOTFILES_TESTS}/suites.manifest"
    return 0
  fi
  local audit="${ARI_DOTFILES_SRC}/docs/test-audit.md" manifest="${ARI_DOTFILES_SUITES_MANIFEST:-${tests}/suites.manifest}"
  local -i owed=0 held=0
  [[ -r "${manifest}" ]] && held="$(awk '!/^#/ && NF >= 2' "${manifest}" | wc -l | tr -d ' ')"
  [[ -r "${audit}" ]] && owed="$(grep -c '| needs a suite' "${audit}" || true)"
  verdict ok documented -d "${hermetic} hermetic and ${suites} plugin suites say what they test; ${bare} plugins have no suite; ${held} audited units hold their suite, ${owed} still need one"
}
