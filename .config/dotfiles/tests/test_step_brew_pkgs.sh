#!/usr/bin/env bash
# brew_pkgs: verdicts from the bundle-check transcripts, dry-run apply, the one real install,
# and the conflict case where an install must never run.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift

check_pkgs() { bump_now_secs 60; nm check --only brew,brew_pkgs --json; out_json > /dev/null; }

world_bundle_check tap
check_pkgs
assert_eq "tap-only exits 0" 0 "${RC}"
assert_eq "tap-only is warn" warn "$(step_get brew_pkgs .status)"
assert_eq "tap-only reason missing_tap" missing_tap "$(step_get brew_pkgs .reason)"
assert_eq "tap-only is actionable" true "$(step_get brew_pkgs .actionable)"
assert_eq "tap item tier global" global "$(step_get brew_pkgs '.items[0].tier')"
assert_eq "tap item name" homebrew/autoupdate "$(step_get brew_pkgs '.items[0].name')"

world_bundle_check mixed
check_pkgs
assert_eq "mixed exits 1" 1 "${RC}"
assert_eq "mixed is fail" fail "$(step_get brew_pkgs .status)"
assert_eq "mixed reason missing" missing "$(step_get brew_pkgs .reason)"
assert_eq "mixed is actionable" true "$(step_get brew_pkgs .actionable)"

world_bundle_check unlinked
check_pkgs
assert_eq "unlinked is fail" fail "$(step_get brew_pkgs .status)"
assert_eq "unlinked reason brewfile_conflict" brewfile_conflict "$(step_get brew_pkgs .reason)"
assert_eq "conflict is manual" true "$(step_get brew_pkgs .manual)"
assert_eq "conflict is not actionable" false "$(step_get brew_pkgs .actionable)"

assert_no_mutation "check mode made only read-only brew calls"
unexpected="$(grep -vE '^(--version|--prefix|--cellar|--caskroom|--repository|list |tap$|tap-info |info |bundle list |bundle check )' "${BREW_SHIM_LOG_DIR}/brew.log" || true)"
assert_eq "every brew call is on the check-mode allowlist" "" "${unexpected}"

world_bundle_check tap
bump_now_secs 60
nm setup --only brew,brew_pkgs --dry-run
assert_eq "setup --dry-run exits 0" 0 "${RC}"
# §2.4: dry-run prints the apply plan and never enters an apply, so the plan line is asserted.
assert_contains "dry-run logs the apply it would run" "${ERR}" "would run apply::brew_pkgs"
assert_contains "dry-run plan names the install" "$(cat "$(newest_run_dir)/brew_pkgs.log")" "dry-run, would run | cmd='brew bundle install --no-upgrade --file="
assert_not_contains "dry-run never enters the apply" "$(shim_log brew)" "bundle install"
assert_no_mutation "dry-run never mutates"

export BREW_SHIM_ALLOW_MUTATION=1
bump_now_secs 60
nm setup --only brew,brew_pkgs --json
out_json > /dev/null
assert_contains "setup ran the install" "$(shim_log brew)" "MUTATION bundle install --no-upgrade --file="
assert_eq "fixture unchanged → apply_did_not_converge" apply_did_not_converge "$(step_get brew_pkgs .reason)"
assert_eq "applied recorded" true "$(step_get brew_pkgs .applied)"

world_bundle_check unlinked
shim_logs_reset
bump_now_secs 60
nm setup --only brew,brew_pkgs --json
out_json > /dev/null
assert_not_contains "conflict never triggers bundle install" "$(shim_log brew)" "bundle install"
assert_eq "conflict stays fail under setup" fail "$(step_get brew_pkgs .status)"
unset BREW_SHIM_ALLOW_MUTATION

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${FIX}/out.json" >&2; fi
report
