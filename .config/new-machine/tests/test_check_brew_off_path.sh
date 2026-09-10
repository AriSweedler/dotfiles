#!/usr/bin/env bash
# brew off PATH (launchd's world): found through NEW_MACHINE_BREW_PREFIXES, or a clean fail.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
mkdir -p "${FIX}/opt/homebrew/bin"
cp "${TESTS_DIR}/shims/brew" "${FIX}/opt/homebrew/bin/brew"
chmod +x "${FIX}/opt/homebrew/bin/brew"
shim_remove brew

export NEW_MACHINE_BREW_PREFIXES="${FIX}/opt/homebrew"
nm check --only brew --json
f="$(out_json)"
assert_eq "brew found through the prefix probe" ok "$(step_get brew .status)"
assert_contains "probe used the prefix path" "$(step_get brew .detail)$(step_get brew .reason)${ERR}" "Homebrew"

export NEW_MACHINE_BREW_PREFIXES=""
bump_now_secs 60
nm check --json
assert_eq "check without brew exits 1" 1 "${RC}"
f="$(out_json)"
assert_eq "brew fails" fail "$(step_get brew .status)"
assert_eq "brew reason brew_missing" brew_missing "$(step_get brew .reason)"
for step in brew_pkgs brew_drift terminal_nerdfont; do
  assert_eq "${step} skipped" skip "$(step_get "${step}" .status)"
  assert_eq "${step} reason prerequisite_fail" prerequisite_fail "$(step_get "${step}" .reason)"
done
assert_json "12 steps recorded" "${f}" '.steps|length' 12

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
