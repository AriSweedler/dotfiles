#!/usr/bin/env bash
# The step runner: a failing step never stops the others, brew is the one hard prerequisite,
# --only selects exactly the named steps.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export BOB_SHIM_LS="Installed: v0.11.2 Used"

export DOTFILES_REMOTE="${FIX}/remotes/no-such-remote.git"
export BREW_SHIM_ALLOW_MUTATION=1
nm setup --json
assert_eq "setup with a bad remote exits 1" 1 "${RC}"
f="$(out_json)"
assert_eq "dotfiles_repo fails" fail "$(step_get dotfiles_repo .status)"
ldf_status="$(step_get local_dotfiles_repo .status)"
if [[ "${ldf_status}" == ok || "${ldf_status}" == warn ]]; then pass "local_dotfiles_repo still ran and passed (${ldf_status})"
else fail "local_dotfiles_repo still ran and passed" "status='${ldf_status}'"; fi
assert_file "local repo was created despite the earlier failure" "${NEW_MACHINE_LDF_GIT_DIR}/HEAD"
assert_json "every step recorded" "${f}" '.steps|length' "${EXPECTED_STEPS}"
unset BREW_SHIM_ALLOW_MUTATION
export DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"

shim_remove brew
export NEW_MACHINE_BREW_PREFIXES=""
bump_now_secs 60
nm setup --dry-run --json
f="$(out_json)"
assert_eq "brew would be installed" fail "$(step_get brew .status)"
assert_eq "brew applied=would_apply" would_apply "$(step_get brew .applied)"
assert_contains "dry-run logs the brew install plan" "${ERR}" "would run apply::brew"
assert_contains "dry-run plan names the Homebrew installer" "$(cat "$(newest_run_dir)/brew.log")" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
assert_eq "curl never called" "" "$(shim_log curl)"
assert_json "remaining steps skip aborted" "${f}" '[.steps[] | select(.step != "brew")] | all(.status == "skip" and .reason == "aborted")' true
assert_json "every step recorded after the abort" "${f}" '.steps|length' "${EXPECTED_STEPS}"

bump_now_secs 60
nm check --json
assert_eq "check without brew exits 1" 1 "${RC}"
f="$(out_json)"
assert_eq "brew fails" fail "$(step_get brew .status)"
assert_eq "brew reason brew_missing" brew_missing "$(step_get brew .reason)"
for step in brew_pkgs brew_drift terminal_nerdfont; do
  assert_eq "${step} skip" skip "$(step_get "${step}" .status)"
  assert_eq "${step} reason prerequisite_fail" prerequisite_fail "$(step_get "${step}" .reason)"
done
assert_json "non-brew steps still ran" "${f}" '[.steps[] | select(.step=="claude" or .step=="bob_neovim" or .step=="dotfiles_repo" or .step=="local_dotfiles_repo") | .status] | all(. != "skip")' true

shim_add brew
bump_now_secs 60
nm check --only brew_drift,claude --json
f="$(out_json)"
assert_json "--only runs exactly the named steps" "${f}" '[.steps[].step] | sort | join(",")' "brew_drift,claude"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${f}" >&2; fi
report
