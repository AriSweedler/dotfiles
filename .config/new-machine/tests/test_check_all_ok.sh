#!/usr/bin/env bash
# A machine at baseline: `check` is green, read-only, and leaves no Desktop file.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export BOB_SHIM_LS="Installed: v0.11.2 Used"

nm check --json
assert_eq "check exits 0" 0 "${RC}"
f="$(out_json)"
assert_json "12 steps ran" "${f}" '.steps|length' 12
assert_json "no step failed or errored" "${f}" '[.steps[] | select(.status=="fail" or .status=="error") | .step + "=" + .reason] | join(",")' ""
# terminal_nerdfont's manual reminder is the one warn the spec lets a green machine carry.
assert_json "status ok" "${f}" '.status=="ok" or (.status=="warn" and ([.steps[] | select(.status=="warn")] | all(.step=="terminal_nerdfont" and .reason=="manual_font")))' true
assert_no_file "no Desktop report" "${NEW_MACHINE_DESKTOP_DIR}/new-machine-FAILED.md"
assert_no_mutation "check is read-only"
assert_file "last-check.json written" "${NEW_MACHINE_STATE_DIR}/last-check.json"
assert_json "last-check.json is the summary" "${NEW_MACHINE_STATE_DIR}/last-check.json" '.mode' check

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
