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
  export BOB_SHIM_LS="Installed: v0.11.2 Used"
  export ARI_DOTFILES_INVOKED_BY=launchd
  export ARI_DOTFILES_RETRY_SECS=0
  REPORT="${ARI_DOTFILES_DESKTOP_DIR}/${REPORT_NAME}"
  LR="${ARI_DOTFILES_STATE_DIR}/last_result.json"
}
verify() { bump_now_secs 60; shim_logs_reset; nm verify; }

# ── transient: brew busy ──────────────────────────────────────────────────────
green_world
mkdir -p "${ARI_DOTFILES_STATE_DIR}"
jq -n '{schema: 1, run_id: "20260901T100500", ts: "2026-09-01T10:05:00Z", status: "fail", fingerprint: "deadbeefdeadbeef",
        first_seen: "2026-09-01", weeks_failing: 1, report_path: null, report_sha256: null, consecutive_errors: 0,
        brew_undeclared: ["formula/x"]}' > "${LR}"
start_busy_brew
verify
assert_eq "busy verify exits 2" 2 "${RC}"
assert_no_file "transient error files no report" "${REPORT}"
assert_json "consecutive_errors 1" "${LR}" '.consecutive_errors' 1
assert_json "fail fingerprint untouched" "${LR}" '.fingerprint' deadbeefdeadbeef
assert_json "brew_undeclared untouched" "${LR}" '.brew_undeclared | join(",")' "formula/x"
assert_contains "notifier says could not run" "$(shim_log terminal-notifier)" "could not run"
assert_contains "notifier names the reason" "$(shim_log terminal-notifier)" "brew_busy"

bump_now 7
verify
assert_eq "second busy verify exits 2" 2 "${RC}"
assert_json "consecutive_errors 2" "${LR}" '.consecutive_errors' 2
assert_file "second consecutive error files the ERROR report" "${REPORT}"
assert_contains "marker kind=error" "$(head -n 1 "${REPORT}")" "kind=error"
assert_contains "ERROR section" "$(cat "${REPORT}")" "## The check itself could not run"
assert_contains "ERROR report names brew_busy" "$(cat "${REPORT}")" "brew_busy"
assert_contains "ERROR Claude task" "$(cat "${REPORT}")" "Diagnose why 'dotfiles healthcheck' cannot run"
assert_no_mutation "erroring verify is read-only"
world_teardown

# ── non-transient: unparsed bundle check output ───────────────────────────────
green_world
world_bundle_check garbage
verify
assert_eq "garbage verify exits 2" 2 "${RC}"
assert_file "non-transient error files a report on the first run" "${REPORT}"
assert_contains "marker kind=error" "$(head -n 1 "${REPORT}")" "kind=error"
assert_contains "report quotes the unparsed line" "$(cat "${REPORT}")" "Something odd happened to foo."
assert_json "consecutive_errors 1" "${LR}" '.consecutive_errors' 1
world_teardown

# ── retry: the fixture flips to satisfied after the first bundle check ────────
green_world
export ARI_DOTFILES_RETRY_SECS=1
world_bundle_check garbage
(
  for _ in $(printf '%s ' {1..200}); do
    if [[ -f "${BREW_SHIM_LOG_DIR}/brew.log" ]] && grep -q 'bundle check' "${BREW_SHIM_LOG_DIR}/brew.log"; then break; fi
    sleep 0.05
  done
  cp "${BREW_SHIM_FIXTURE}/bundle_check.satisfied.out" "${BREW_SHIM_FIXTURE}/bundle_check.out"
  cp "${BREW_SHIM_FIXTURE}/bundle_check.satisfied.rc" "${BREW_SHIM_FIXTURE}/bundle_check.rc"
) &
flipper=$!
WORLD_PIDS+=("${flipper}")
verify
wait "${flipper}" 2>/dev/null || true
assert_eq "verify with a successful retry exits 0" 0 "${RC}"
assert_json "brew_pkgs ok after the retry" "${ARI_DOTFILES_STATE_DIR}/last-check.json" '.steps[] | select(.step=="brew_pkgs") | .status' ok
assert_json "run status ok or warn" "${ARI_DOTFILES_STATE_DIR}/last-check.json" '.status == "ok" or .status == "warn"' true
assert_eq "bundle check ran twice" 2 "$(grep -c 'bundle check' "${BREW_SHIM_LOG_DIR}/brew.log")"
assert_no_file "no report after a recovered run" "${REPORT}"
assert_json "fingerprint empty after the recovered pass" "${LR}" '.fingerprint' ""
assert_json "no consecutive errors after recovery" "${LR}" '.consecutive_errors' 0

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
