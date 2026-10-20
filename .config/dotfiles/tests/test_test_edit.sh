#!/usr/bin/env bash
# `test --edit NAME` opens a suite and the code it tests in one editor call, then runs that suite
# and exits with its status; nothing is committed. `test NAME` finds a plugin suite first, then a
# hermetic one, and ungates a plugin suite under run_tests.zsh's variable (zsh-vi-mode → _).
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
PLUG="${FIX}/plugins"
SUITES="${FIX}/tests"
mkdir -p "${PLUG}" "${SUITES}"
export ARI_DOTFILES_ZSH_PLUGINS="${PLUG}" ARI_DOTFILES_TESTS="${SUITES}"
STEPS="${ORIG_CONFIG_DIR}/dotfiles/steps"
CMD="${ORIG_CONFIG_DIR}/dotfiles/cmd"

# plugin NAME LINE1 RC: NAME.zsh and NAME.test.zsh, which exits RC only when its gate is set.
plugin() {
  local var
  var="OTTO_TEST__ZSH_PLUGINS_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
  printf '# %s\n' "$1" > "${PLUG}/$1.zsh"
  printf '%s\n[[ "${%s:-}" == true ]] || { print -r -- "gated %s"; exit 9; }\nprint -r -- "ran %s"\nexit %s\n' \
    "$2" "${var}" "$1" "$1" "$3" > "${PLUG}/$1.test.zsh"
}
plugin foo '# Tests for foo.zsh — the foo helpers.' 0
plugin zsh-vi-mode '# Tests for zsh-vi-mode.zsh.' 0
plugin broken '# Tests for broken.zsh.' 7
plugin tilde '# Tests for ~/.config/bin/dotfiles.' 0
plugin ghost '# Tests for nowhere.zsh.' 0
# hermetic NAME RC: tests/test_NAME.sh, which prints the dotfiles variables it inherited.
hermetic() {
  printf '#!/usr/bin/env bash\n# %s: a fixture suite.\nprintf "state=%%s bless=%%s\\n" "${ARI_DOTFILES_STATE_DIR:-unset}" "${ARI_DOTFILES_BLESS_GOLDEN:-unset}"\nexit %s\n' \
    "$1" "$2" > "${SUITES}/test_$1.sh"
}
hermetic bar 0
hermetic step_brew_drift 0
hermetic alttab_step 0
hermetic verify_lock 4
printf '#!/usr/bin/env bash\n# the runner\n' > "${SUITES}/run.sh"

EDITORS="${FIX}/editors"
OPENED="${FIX}/opened"
mkdir -p "${EDITORS}"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\n' "${OPENED}" > "${EDITORS}/record"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\nexit 3\n' "${OPENED}" > "${EDITORS}/fail"
chmod +x "${EDITORS}"/*

# t EDITOR ARGS...: `dotfiles test ARGS` with that editor, no terminal.
t() {
  local ed="$1"; shift
  rm -f "${OPENED}"
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" test "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
opened() { cat "${OPENED}" 2>/dev/null; }
lines() { printf '%s\n' "$@"; }
df_before="$(git --git-dir="${ARI_DOTFILES_DF_GIT_DIR}" rev-list --count HEAD 2>/dev/null || echo none)"

# ── `test NAME`: a plugin suite under its gate; the run_tests.zsh spelling of a dash ──
t record foo
assert_eq "plugin suite: exit 0" 0 "${RC}"
assert_eq "plugin suite: ungated" "ran foo" "${OUT}"
t record zsh-vi-mode
assert_eq "dashed name: exit 0" 0 "${RC}"
assert_eq "dashed name: ungated as ZSH_VI_MODE" "ran zsh-vi-mode" "${OUT}"
t record foo.test.zsh
assert_eq "plugin suite by file name" "ran foo" "${OUT}"
t record broken
assert_eq "plugin suite's status is the exit" 7 "${RC}"

# ── `test NAME`: a hermetic suite when no plugin suite has the name; the env it runs in ──
t record bar
assert_eq "hermetic suite: exit 0" 0 "${RC}"
assert_eq "hermetic suite: none of this process's ARI_DOTFILES_* reach it" "state=unset bless=unset" "${OUT}"
t record test_bar.sh
assert_eq "hermetic suite by file name" 0 "${RC}"
hermetic_env
RC=0
env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_BLESS_GOLDEN=1 "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" test bar \
  < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
assert_eq "hermetic suite: ARI_DOTFILES_BLESS_GOLDEN passes" "state=unset bless=1" "$(cat "${FIX}/nm.out")"
t record verify_lock
assert_eq "hermetic suite's status is the exit" 4 "${RC}"
t record nosuch
assert_eq "unknown NAME: 64" 64 "${RC}"
assert_contains "unknown NAME: says so" "${ERR}" "no such suite | name='nosuch'"
t record ../foo
assert_eq "a path is not a NAME" 64 "${RC}"

# ── --edit: the suite and its code in one call, then the suite ──
t record --edit foo
assert_eq "edit plugin: exit 0" 0 "${RC}"
assert_eq "edit plugin: the suite and its '# Tests for' target" "$(lines "${PLUG}/foo.test.zsh" "${PLUG}/foo.zsh")" "$(opened)"
assert_contains "edit plugin: ran the suite" "${OUT}" "ran foo"
assert_contains "edit plugin: nothing committed" "${OUT}" "test: passed; nothing committed"
assert_contains "edit plugin: next" "${OUT}" "next: dotfiles test"
t record --edit tilde
assert_eq "edit: a ~/.config target is read from this checkout" "$(lines "${PLUG}/tilde.test.zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles")" "$(opened)"
t record --edit ghost
assert_eq "edit: a target that does not exist opens the suite alone" "${PLUG}/ghost.test.zsh" "$(opened)"
t record --edit broken
assert_eq "edit: the suite's status is the exit" 7 "${RC}"
assert_contains "edit: a failure names the re-edit" "${OUT}" "next: dotfiles test --edit broken"
t record --edit step_brew_drift
assert_eq "edit test_step_X: steps/X.zsh" "$(lines "${SUITES}/test_step_brew_drift.sh" "${STEPS}/brew_drift.zsh")" "$(opened)"
t record --edit alttab_step
assert_eq "edit test_X_step: steps/X.zsh" "$(lines "${SUITES}/test_alttab_step.sh" "${STEPS}/alttab.zsh")" "$(opened)"
t record --edit verify_lock
assert_eq "edit test_V_*: cmd/V.zsh and cmd/V/*" "$(lines "${SUITES}/test_verify_lock.sh" "${CMD}/verify.zsh" "${CMD}/verify/report.zsh")" "$(opened)"
assert_eq "edit test_V_*: the suite's status" 4 "${RC}"
t record --edit bar
assert_eq "edit: no code to pair, the suite alone" "${SUITES}/test_bar.sh" "$(opened)"
t record bar --edit
assert_eq "edit: the flag after NAME" "${SUITES}/test_bar.sh" "$(opened)"

# The editor fails: exit 1 and nothing runs.
t fail --edit foo
assert_eq "editor fails: exit 1" 1 "${RC}"
assert_not_contains "editor fails: the suite did not run" "${OUT}" "ran foo"
assert_contains "editor fails: says so" "${ERR}" "editor exited non-zero; nothing run"
t record --edit nosuch
assert_eq "edit unknown NAME: 64" 64 "${RC}"
assert_eq "edit unknown NAME: no editor" "" "$(opened)"

# No NAME: the runner, opened and not run.
t record --edit
assert_eq "edit runner: exit 0" 0 "${RC}"
assert_eq "edit runner: tests/run.sh" "${SUITES}/run.sh" "$(opened)"
assert_contains "edit runner: next" "${OUT}" "next: dotfiles test"
t fail --edit
assert_eq "edit runner, editor fails: exit 1" 1 "${RC}"
t record a b
assert_eq "two NAMEs: 64" 64 "${RC}"

assert_eq "nothing committed" "${df_before}" "$(git --git-dir="${ARI_DOTFILES_DF_GIT_DIR}" rev-list --count HEAD 2>/dev/null || echo none)"
nm test --help
assert_contains "help: edit in Usage" "${OUT}" "dotfiles test edit [NAME]"
assert_contains "help: the edit subcommand" "${OUT}" "  edit  open NAME's suite and the code it tests"
assert_contains "help: --edit in Flags" "${OUT}" "  --edit  edit: the same as the edit subcommand"
assert_no_mutation "nothing reaches brew"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
