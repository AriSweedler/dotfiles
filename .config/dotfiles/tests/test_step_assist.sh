#!/usr/bin/env bash
# The runner's assist hook: in setup, a manual fail of a step that defines assist:: is handed to it
# at a terminal; a 0 re-checks and records the new verdict, anything else keeps the fail. Never in
# check mode, under --dry-run, with ARI_DOTFILES_ASSIST=off, or off a terminal.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
# A program whose steps/ holds only the fixture: lib/ and zsh/ are the checkout under test, and
# ARI_DOTFILES_LIB (which env.zsh honours) points the kernel, and every isolated check, at it.
PROG="${FIX}/prog"
STEPS_DIR="${PROG}/dotfiles/steps"
mkdir -p "${STEPS_DIR}"
ln -s "${ORIG_CONFIG_DIR}/dotfiles/lib" "${PROG}/dotfiles/lib"
ln -s "${ORIG_CONFIG_DIR}/zsh" "${PROG}/zsh"
cat > "${STEPS_DIR}/zz_manual.zsh" <<'EOF'
# step zz_manual — a manual fail a human fixes when the runner assists
step::declare zz_manual --desc "a fake manual step" --assist "asks whether to fix it now"
step::watches zz_manual --none "a test fixture"
check::zz_manual() {
  if [[ -e "${T_FIX}/fixed" ]]; then
    verdict ok fixed -d "fixed by hand"
    return 0
  fi
  verdict fail broken -m -d "broken" -f "fix it by hand"
}
assist::zz_manual() {
  print -r -- called >> "${T_FIX}/assist.log"
  [[ "${T_ASSIST_FIXES}" == 1 ]] || return 1
  : > "${T_FIX}/fixed"
}
EOF

# runstep <tty 0|1> <assist fixes 0|1> [env..]: step::run zz_manual in setup mode (unless the env
# says otherwise), with run::_has_tty standing in for the terminal.
runstep() {
  local tty="$1" fixes="$2"; shift 2
  hermetic_env
  rm -rf "${FIX}/run" "${FIX}/fixed" "${FIX}/assist.log"
  mkdir -p "${FIX}/run"
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_LIB="${PROG}/dotfiles/lib" RUN_DIR="${FIX}/run" ARI_DOTFILES_UI=plain \
    ARI_DOTFILES_MODE=setup T_FIX="${FIX}" T_TTY="${tty}" T_ASSIST_FIXES="${fixes}" "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "${ARI_DOTFILES_STEPS}/zz_manual.zsh"
      run::_has_tty() { [[ "${T_TTY}" == 1 ]]; }
      step::run zz_manual' _ "${PROG}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
  RESULT="$(cat "${FIX}/run/zz_manual.result.json" 2>/dev/null || true)"
  CALLS="$(grep -c called "${FIX}/assist.log" 2>/dev/null || true)"
}
result() { printf '%s' "${RESULT}" | jq -r "[.status, .reason, (.applied | tostring)] | join(\" \")"; }

runstep 1 1
assert_eq "at a terminal, the assist that fixes it is called once" 1 "${CALLS}"
assert_eq "at a terminal, a fixed assist re-checks: ok, applied" "ok fixed true" "$(result)"

runstep 1 0
assert_eq "at a terminal, a declined assist is called once" 1 "${CALLS}"
assert_eq "at a terminal, a declined assist keeps the manual fail" "fail broken false" "$(result)"

runstep 0 1
assert_eq "off a terminal, no assist" "" "${CALLS}"
assert_eq "off a terminal, the manual fail stands" "fail broken false" "$(result)"

runstep 1 1 ARI_DOTFILES_ASSIST=off
assert_eq "ARI_DOTFILES_ASSIST=off, no assist" "" "${CALLS}"

runstep 1 1 ARI_DOTFILES_DRY_RUN=1
assert_eq "dry run, no assist" "" "${CALLS}"
assert_contains "dry run, says it would offer one" "$(cat "${FIX}/run/run.log" 2>/dev/null; cat "${FIX}/err")" "would offer assist::zz_manual"

runstep 1 1 ARI_DOTFILES_MODE=check
assert_eq "check mode, no assist" "" "${CALLS}"
assert_eq "check mode, the manual fail stands" "fail broken false" "$(result)"

runstep 1 1 ARI_DOTFILES_INVOKED_BY=launchd
assert_eq "under launchd, no assist" "" "${CALLS}"

report
