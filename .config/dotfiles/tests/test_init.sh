#!/usr/bin/env bash
# `dotfiles init`: setup's repo group under the lock, then status; nothing outside the group
# runs; a converged machine applies nothing; --dry-run mutates nothing; extra arguments are usage.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
REPO_GROUP="claude_skills,dotfiles_jobs,dotfiles_repo,local_dotfiles_repo,ssh_key"

nm init
assert_eq "init exits 0" 0 "${RC}"
assert_contains "init prints the run table" "${OUT}" "dotfiles_repo"
assert_not_contains "init runs no brew step" "${OUT}" "brew_pkgs"
assert_contains "init ends with status" "${OUT}" "tiers"
assert_contains "status shows the shared tier" "${OUT}" "shared:"
assert_contains "status shows the local tier" "${OUT}" "local:"
assert_no_file "lock released" "${ARI_DOTFILES_STATE_DIR}/lock.d"
assert_file "the run is a setup" "${ARI_DOTFILES_STATE_DIR}/last-setup.json"
assert_json "the run is the repo group" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" '[.steps[].step] | sort | join(",")' "${REPO_GROUP}"
assert_json "no step failed or errored" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" '[.steps[] | select(.status=="fail" or .status=="error") | .step + "=" + .reason] | join(",")' ""
assert_json "converged machine applies nothing" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" '[.steps[] | select(.applied == true)] | length' 0
assert_no_mutation "converged init mutates nothing"

bump_now_secs 60
nm init --dry-run
assert_eq "init --dry-run exits 0" 0 "${RC}"
assert_contains "dry-run announces itself" "${ERR}" "dry-run: no changes will be made"
assert_contains "dry-run still ends with status" "${OUT}" "tiers"
assert_no_mutation "dry-run mutates nothing"

nm init extra
assert_eq "init with arguments exits 64" 64 "${RC}"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${ARI_DOTFILES_STATE_DIR}/last-setup.json" >&2; printf '%s\n' "${OUT}" "${ERR}" | tail -n 30 >&2; fi
report
