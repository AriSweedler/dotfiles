#!/usr/bin/env bash
# tmux_server: skip with no tmux or no server, ok when the server runs PATH's tmux, warn when it
# runs another one, fail when its binary is gone; both are hand fixes (a restart ends sessions).
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

check_tmux() { bump_now_secs 60; nm check --only tmux_server --json; out_json > /dev/null; }
status_of() { step_get tmux_server .status; }
reason_of() { step_get tmux_server .reason; }

unset TMUX_SHIM_PID LSOF_SHIM_EXE
check_tmux
assert_eq "no server → skip" skip "$(status_of)"
assert_eq "reason no_server" no_server "$(reason_of)"

export TMUX_SHIM_PID=4242
check_tmux
assert_eq "server runs PATH's tmux → ok" ok "$(status_of)"
assert_eq "reason server_current" server_current "$(reason_of)"
assert_contains "lsof asked for the server's txt" "$(shim_log lsof)" "-p 4242 -d txt"

other="${FIX}/old-tmux"
printf '#!/bin/sh\n' > "${other}"
export LSOF_SHIM_EXE="${other}"
check_tmux
assert_eq "server runs another tmux → warn" warn "$(status_of)"
assert_eq "reason server_stale" server_stale "$(reason_of)"
assert_eq "server_stale is manual" true "$(step_get tmux_server .manual)"
assert_contains "fix restarts tmux" "$(step_get tmux_server .fix)" "kill-server"

export LSOF_SHIM_EXE="${FIX}/gone/opt/homebrew/Cellar/tmux/3.7c/bin/tmux"
check_tmux
assert_eq "server binary deleted → fail" fail "$(status_of)"
assert_eq "reason server_binary_gone" server_binary_gone "$(reason_of)"
assert_eq "server_binary_gone is manual" true "$(step_get tmux_server .manual)"
assert_contains "detail names the deleted binary" "$(step_get tmux_server .detail)" "Cellar/tmux/3.7c"

export LSOF_SHIM_EXE=""
check_tmux
assert_eq "lsof reads no executable → warn" warn "$(status_of)"
assert_eq "reason server_unread" server_unread "$(reason_of)"
unset LSOF_SHIM_EXE

shim_remove tmux
check_tmux
assert_eq "no tmux → skip" skip "$(status_of)"
assert_eq "reason no_tmux" no_tmux "$(reason_of)"
unset TMUX_SHIM_PID

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, fix}' "${FIX}/out.json" >&2; fi
report
