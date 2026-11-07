#!/usr/bin/env bash
# ERROR handling in verify: transient errors nag only on the second consecutive run and never
# touch the fail fingerprint; non-transient errors file immediately; the in-job retry works.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPORT_NAME="new-machine-FAILED.md"

green_world() {
  world_new
  world_use_fixture satisfied
  seed_fake_repos
  seed_ldf_remote
  seed_home_baseline
  export ARI_DOTFILES_INVOKED_BY=launchd
  export ARI_DOTFILES_RETRY_SECS=0
  REPORT="${ARI_DOTFILES_DESKTOP_DIR}/${REPORT_NAME}"
  LR="${ARI_DOTFILES_STATE_DIR}/last_result.json"
}
verify() { bump_now_secs 60; shim_logs_reset; nm verify; }

# ── transient: a check timed out ─────────────────────────────────────────────
green_world
mkdir -p "${ARI_DOTFILES_STATE_DIR}"
jq -n '{schema: 1, run_id: "20260901T100500", ts: "2026-09-01T10:05:00Z", status: "fail", fingerprint: "deadbeefdeadbeef",
        first_seen: "2026-09-01", weeks_failing: 1, report_path: null, report_sha256: null, consecutive_errors: 0}' > "${LR}"
export ARI_DOTFILES_CHECK_TIMEOUT_SECS=1 NVIM_SHIM_HANG=1
verify
assert_eq "timed-out verify exits 2" 2 "${RC}"
assert_no_file "transient error files no report" "${REPORT}"
assert_json "consecutive_errors 1" "${LR}" '.consecutive_errors' 1
assert_json "fail fingerprint untouched" "${LR}" '.fingerprint' deadbeefdeadbeef
assert_contains "notifier says could not run" "$(shim_log atn)" "could not run"
assert_contains "notifier names the reason" "$(shim_log atn)" "timed_out"

bump_now 7
verify
assert_eq "second timed-out verify exits 2" 2 "${RC}"
assert_json "consecutive_errors 2" "${LR}" '.consecutive_errors' 2
assert_file "second consecutive error files the ERROR report" "${REPORT}"
assert_contains "marker kind=error" "$(head -n 1 "${REPORT}")" "kind=error"
assert_contains "ERROR section" "$(cat "${REPORT}")" "## The check itself could not run"
assert_contains "ERROR report names timed_out" "$(cat "${REPORT}")" "timed_out"
assert_contains "ERROR Claude task" "$(cat "${REPORT}")" "Diagnose why 'dotfiles healthcheck' cannot run"
assert_no_mutation "erroring verify is read-only"
unset ARI_DOTFILES_CHECK_TIMEOUT_SECS NVIM_SHIM_HANG
world_teardown

# ── non-transient: the allowlist template is gone ────────────────────────────
green_world
TEMPLATE="${HOME}/.config/new-machine/local-dotfiles-exclude"
mv "${TEMPLATE}" "${FIX}/template.away"
verify
assert_eq "template-missing verify exits 2" 2 "${RC}"
assert_file "non-transient error files a report on the first run" "${REPORT}"
assert_contains "marker kind=error" "$(head -n 1 "${REPORT}")" "kind=error"
assert_contains "report names the reason" "$(cat "${REPORT}")" "template_missing"
assert_json "consecutive_errors 1" "${LR}" '.consecutive_errors' 1
world_teardown

# ── retry: the template comes back after the first check ─────────────────────
# The flip waits for the runner's retry line, written once the first check has finished, so it
# never lands under that first check on a loaded machine (which then passes and never retries).
green_world
export ARI_DOTFILES_RETRY_SECS=2
TEMPLATE="${HOME}/.config/new-machine/local-dotfiles-exclude"
mv "${TEMPLATE}" "${FIX}/template.away"
(
  for _ in $(printf '%s ' {1..400}); do
    if cat "${ARI_DOTFILES_STATE_DIR}"/runs/*/run.log 2>/dev/null | grep -q 'retrying errored steps'; then break; fi
    sleep 0.05
  done
  mv "${FIX}/template.away" "${TEMPLATE}"
) &
flipper=$!
WORLD_PIDS+=("${flipper}")
verify
wait "${flipper}" 2>/dev/null || true
assert_eq "verify with a successful retry exits 0" 0 "${RC}"
assert_json "local_dotfiles_repo recovered after the retry" "${ARI_DOTFILES_STATE_DIR}/last-check.json" '.steps[] | select(.step=="local_dotfiles_repo") | .status != "error"' true
assert_json "run status ok or warn" "${ARI_DOTFILES_STATE_DIR}/last-check.json" '.status == "ok" or .status == "warn"' true
assert_no_file "no report after a recovered run" "${REPORT}"
assert_json "fingerprint empty after the recovered pass" "${LR}" '.fingerprint' ""
assert_json "no consecutive errors after recovery" "${LR}" '.consecutive_errors' 0

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
