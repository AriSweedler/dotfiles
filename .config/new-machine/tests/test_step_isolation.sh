#!/usr/bin/env bash
# One failing or crashing check never hides the others; garbage output is a loud error.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_home_baseline
export BOB_SHIM_RC=3
shim_remove claude

nm check --json
assert_eq "check exits 1" 1 "${RC}"
f="$(out_json)"
assert_eq "bob_neovim fails" fail "$(step_get bob_neovim .status)"
assert_eq "claude fails" fail "$(step_get claude .status)"
assert_eq "claude reason claude_missing" claude_missing "$(step_get claude .reason)"
for step in terminal_nerdfont karabiner claude_notifications git_health weekly_verify; do
  status="$(step_get "${step}" .status)"
  if [[ -n "${status}" && "${status}" != null ]]; then pass "${step} ran after the failures (${status})"
  else fail "${step} ran after the failures" "status='${status}'"; fi
done
assert_json "12 steps recorded" "${f}" '.steps|length' 12

unset BOB_SHIM_RC
world_bundle_check garbage
bump_now_secs 60
nm check --only brew,brew_pkgs --json
assert_eq "garbage bundle check exits 2" 2 "${RC}"
f="$(out_json)"
assert_eq "brew_pkgs is error" error "$(step_get brew_pkgs .status)"
assert_eq "brew_pkgs reason bundle_check_unparsed" bundle_check_unparsed "$(step_get brew_pkgs .reason)"
assert_contains "detail quotes the unparsed line" "$(step_get brew_pkgs .detail)" "→ Something odd happened to foo."

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
