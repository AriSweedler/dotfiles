#!/usr/bin/env bash
# The verify lock: a dead holder is cleared, a live one wins (exit 4), an ancient live one is
# taken over.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export BOB_SHIM_LS="Installed: v0.11.2 Used"
export NEW_MACHINE_INVOKED_BY=launchd
STATE="${NEW_MACHINE_STATE_DIR}"
LOCK="${STATE}/lock.d"
verify() { bump_now_secs 60; shim_logs_reset; nm verify; }

# A pid that is certainly dead: a finished sleep.
sleep 0.01 &
dead_pid=$!
wait "${dead_pid}"
mkdir -p "${LOCK}"
printf '%s\n' "${dead_pid}" > "${LOCK}/pid"
verify
if (( RC != 4 )); then pass "dead holder: run proceeds (rc=${RC})"; else fail "dead holder: run proceeds" "exit 4"; fi
assert_no_file "lock released after the run" "${LOCK}"
assert_not_contains "no busy note for a dead holder" "$(cat "${STATE}/verify.log" 2>/dev/null)" "busy"

sleep 300 2>/dev/null &
live_pid=$!
WORLD_PIDS+=("${live_pid}")
mkdir -p "${LOCK}"
printf '%s\n' "${live_pid}" > "${LOCK}/pid"
verify
assert_eq "live holder: exit 4" 4 "${RC}"
assert_file "live holder keeps the lock" "${LOCK}/pid"
assert_eq "live holder's pid file untouched" "${live_pid}" "$(cat "${LOCK}/pid")"
assert_contains "notifier says another run holds the lock" "$(shim_log terminal-notifier)" "holds the lock"
assert_contains "trail notes busy" "$(cat "${STATE}/verify.log")" "busy"

export NEW_MACHINE_LOCK_MAX_AGE_SECS=1
touch -t 202001010000 "${LOCK}"
verify
if (( RC != 4 )); then pass "ancient live holder: run proceeds (rc=${RC})"; else fail "ancient live holder: run proceeds" "exit 4"; fi
assert_contains "trail notes the takeover" "$(cat "${STATE}/verify.log")${ERR}" "stale lock taken over"
assert_no_file "lock released after the takeover run" "${LOCK}"

# A run that exits non-zero must release the lock too: zsh skips the EXIT trap when ERR_EXIT
# ends the shell, so the CLI's exit has to be explicit.
unset NEW_MACHINE_LOCK_MAX_AGE_SECS
shim_remove claude
bump_now_secs 60
nm check --only claude
assert_eq "failing check exits 1" 1 "${RC}"
assert_eq "failing check reports claude_missing" claude_missing "$(jq -r '.steps[] | select(.step=="claude") | .reason' "${STATE}/last-check.json")"
assert_no_file "lock released after a failing check" "${LOCK}"
verify
assert_eq "failing verify exits 1" 1 "${RC}"
assert_no_file "lock released after a failing verify" "${LOCK}"

report
