#!/usr/bin/env bash
# A second `setup` on a converged machine applies nothing: no brew mutation, no commits, no
# launchd bootstrap, no step marked applied.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export ARI_DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"
export BREW_SHIM_ALLOW_MUTATION=1
export BOB_SHIM_LS="Installed: v0.11.2 Used"

nm setup --json
assert_eq "first setup exits 0" 0 "${RC}"
f="$(out_json)"
assert_json "first setup converged" "${f}" '[.steps[] | select(.status=="fail" or .status=="error")] | length' 0

mutations_before="$(grep -c '^MUTATION' "${BREW_SHIM_LOG_DIR}/brew.log" || true)"
bootstraps_before="$(grep -c '^bootstrap' "${BREW_SHIM_LOG_DIR}/launchctl.log" || true)"
df_log_before="$(df_git log --format=%H)"
ldf_log_before="$(git --git-dir="${ARI_DOTFILES_LDF_GIT_DIR}" log --format=%H 2>/dev/null || printf 'unborn')"

bump_now_secs 60
nm setup --json
assert_eq "second setup exits 0" 0 "${RC}"
f="$(out_json)"
assert_eq "no new brew mutation" "${mutations_before}" "$(grep -c '^MUTATION' "${BREW_SHIM_LOG_DIR}/brew.log" || true)"
assert_eq "no new launchctl bootstrap" "${bootstraps_before}" "$(grep -c '^bootstrap' "${BREW_SHIM_LOG_DIR}/launchctl.log" || true)"
assert_eq "dotfiles git log unchanged" "${df_log_before}" "$(df_git log --format=%H)"
assert_eq "local-dotfiles git log unchanged" "${ldf_log_before}" "$(git --git-dir="${ARI_DOTFILES_LDF_GIT_DIR}" log --format=%H 2>/dev/null || printf 'unborn')"
assert_json "no step applied on the second run" "${f}" '[.steps[] | select(.applied == true or .applied == "would_apply")] | length' 0
assert_json "second run has no fail or error" "${f}" '[.steps[] | select(.status=="fail" or .status=="error")] | length' 0
assert_json "every step recorded" "${f}" '.steps|length' "${EXPECTED_STEPS}"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${f}" >&2; fi
report
