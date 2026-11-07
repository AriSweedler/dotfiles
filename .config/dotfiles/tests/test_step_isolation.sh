#!/usr/bin/env bash
# One failing or crashing check never hides the others.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_home_baseline
export NVIM_SHIM_RC=3
shim_remove claude

nm check --json
assert_eq "check exits 1" 1 "${RC}"
f="$(out_json)"
assert_eq "neovim fails" fail "$(step_get neovim .status)"
assert_eq "claude fails" fail "$(step_get claude .status)"
assert_eq "claude reason claude_missing" claude_missing "$(step_get claude .reason)"
for step in terminal_nerdfont karabiner claude_notifications claude_skills dotfiles_jobs; do
  status="$(step_get "${step}" .status)"
  if [[ -n "${status}" && "${status}" != null ]]; then pass "${step} ran after the failures (${status})"
  else fail "${step} ran after the failures" "status='${status}'"; fi
done
assert_steps_are_registry "every step recorded" "${f}"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
