#!/usr/bin/env bash
# `verify` on a drifting machine writes the Desktop report, archives it, records last_result,
# notifies, and mutates nothing.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
shim_remove claude
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export ARI_DOTFILES_INVOKED_BY=launchd
REPORT="${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.md"
STATE="${ARI_DOTFILES_STATE_DIR}"

nm verify
assert_eq "verify exits 1" 1 "${RC}"
assert_file "Desktop report written" "${REPORT}"
first="$(head -n 1 "${REPORT}")"
assert_contains "first line is the marker" "${first}" "<!-- new-machine-report v1 fingerprint="
assert_contains "marker kind=fail" "${first}" "kind=fail"
marker_fp=""
if [[ "${first}" =~ fingerprint=([0-9a-f]{16}) ]]; then marker_fp="${BASH_REMATCH[1]}"; pass "marker carries a 16-hex fingerprint"; else fail "marker carries a 16-hex fingerprint" "${first}"; fi
content="$(cat "${REPORT}")"
assert_contains "What failed" "${content}" "## What failed"
assert_contains "claude row" "${content}" "| claude |"
assert_not_contains "no brew section" "${content}" "brew items"
assert_contains "How to feed this to Claude" "${content}" "## How to feed this to Claude"
assert_contains "the literal claude line" "${content}" "claude \"Read ${REPORT}"
assert_contains "/ari-dotfiles" "${content}" "/ari-dotfiles"
assert_contains "NEVER push" "${content}" "NEVER push"
assert_contains "git ldf push" "${content}" "git ldf push"
assert_contains "Run dotfiles push when ready" "${content}" "Run dotfiles push when ready"
assert_contains "dotfiles test" "${content}" '`dotfiles test` must pass'
assert_contains "What fixed looks like" "${content}" '## What "fixed" looks like'
assert_contains "raw log path under the fake state dir" "${content}" "${STATE}/verify/log.txt"

archives=("${STATE}"/reports/*.md)
assert_eq "one archived report" 1 "${#archives[@]}"
if [[ "$(basename "${archives[0]}")" =~ ^2026-09-10-[0-9a-f]{8}\.md$ ]]; then pass "archive named <date>-<fp8>.md"; else fail "archive named <date>-<fp8>.md" "${archives[0]}"; fi
if cmp -s "${archives[0]}" "${REPORT}"; then pass "archive is byte-identical to the Desktop file"; else fail "archive is byte-identical to the Desktop file" "differs"; fi

LR="${STATE}/last_result.json"
assert_file "last_result.json written" "${LR}"
assert_json "last_result fingerprint matches the marker" "${LR}" '.fingerprint' "${marker_fp}"
assert_json "report_sha256 recorded" "${LR}" '.report_sha256' "$(sha256 "${REPORT}")"
assert_json "first_seen is today" "${LR}" '.first_seen' "2026-09-10"
assert_json "weeks_failing 1" "${LR}" '.weeks_failing' 1
assert_json "status fail" "${LR}" '.status' fail

notif="$(shim_log atn)"
assert_contains "notifier announces problems" "${notif}" "problems"
assert_contains "notifier click opens the report in a tmux editor window" "${notif}" "-execute ${HOME}/.config/bin/tmux-edit-window -n dotfiles ${REPORT}"
assert_not_contains "notifier never hands the report to -open (Xcode)" "${notif}" "-open file://"
assert_no_mutation "verify is read-only"
# One summary line per run; event notes (report written, archived, ...) may accompany it.
assert_eq "verify.log has one status line for the run" 1 "$(grep -c "\[verify\] status=" "${STATE}/verify.log")"
assert_contains "verify.log line names the status" "$(cat "${STATE}/verify.log")" "status='fail'"
assert_contains "verify.log line names the fingerprint" "$(cat "${STATE}/verify.log")" "fingerprint='${marker_fp}'"
assert_file "last-check.json written" "${STATE}/last-check.json"
assert_file "verbose log written" "${STATE}/verify/log.txt"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
