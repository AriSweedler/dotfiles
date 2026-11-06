#!/usr/bin/env zsh
# Tests for ~/.config/claude/lib/tmux-pane.sh on a throwaway tmux server (-L): tmux_pane_gate_check sets one
# stable kind per refusal beside the prose, tmux_pane_gate_refusal still prints the prose and returns the same
# codes, a gone pane reads as 'no such pane' (pane_gone) and never as not opted in, and tmux_pane_lock
# terminates: an unwritable lock root, or a stale lock that will not break, fails at once with
# ARI_DRIVING_EXIT_LOCK_UNAVAILABLE and a message on stderr; a fresh lock times out with 1.
# Never touches the live tmux server, Ari's shell config or his clipboard.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/tests/tmux-pane-lib.test.zsh
set -uo pipefail

readonly LIB="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
readonly T="${TMPDIR:-/tmp}/ari-driving-lib-test-$$"
readonly L="ari-driving-lib-test-$$"
mkdir -p "${T}/locks"

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}

tmux() { command tmux -L "${L}" -f /dev/null "$@"; }
cleanup() { tmux kill-server 2>/dev/null; chmod -R u+rwx "${T}" 2>/dev/null; rm -rf "${T}"; }
trap cleanup EXIT

source "${LIB}"
ARI_DRIVING_LOCK_ROOT="${T}/locks"

tmux new-session -d -s t -x 120 -y 30 "env PS1='❯ ' zsh -f -i"
pane="$(tmux display-message -p -t t '#{pane_id}')"
for _ in {1..50}; do
  [[ "$(tmux capture-pane -p -t "${pane}")" == *'❯'* ]] && break
  sleep 0.1
done

gate() {   # <pane> -> kind|rc|reason via the check; the refusal wrapper's output and rc are checked separately
  tmux_pane_gate_check "${1}" '❯'; local rc=$?
  print -r -- "${ARI_DRIVING_GATE_KIND}|${rc}|${ARI_DRIVING_GATE_REASON}"
}

# --- the kinds ---
check "not opted in" "not_opted_in|77|not opted in; Ari runs 'ari-driving on' in that pane" "$(gate "${pane}")"
tmux set-option -p -t "${pane}" @ari_driving on
check "an idle opted-in prompt passes with no kind" "|0|" "$(gate "${pane}")"

tmux copy-mode -t "${pane}"
check "copy mode" "copy_mode|75|in copy mode (press q there)" "$(gate "${pane}")"
tmux send-keys -t "${pane}" -X cancel
tmux set-window-option -t "${pane}" synchronize-panes on
check "synchronized" "synchronized|75|synchronize-panes is on" "$(gate "${pane}")"
tmux set-window-option -t "${pane}" synchronize-panes off

tmux send-keys -t "${pane}" 'echo busy-text' ''
sleep 0.3
contains "text already on the line" "not_at_prompt|75|last line does not end" "$(gate "${pane}")"
tmux send-keys -t "${pane}" C-u

tmux new-window -d -t t "sleep 60"
other="$(tmux list-panes -t t:1 -F '#{pane_id}')"
tmux set-option -p -t "${other}" @ari_driving on
check "a program in front" "not_a_shell|75|running sleep, not a shell" "$(gate "${other}")"

# --- a gone pane is not 'not opted in' ---
tmux kill-window -t t:1
check "a gone pane is pane_gone" "pane_gone|75|no such pane" "$(gate "${other}")"
check "a gone pane that never existed" "pane_gone|75|no such pane" "$(gate '%9999')"

# --- the prose wrapper is unchanged for existing callers ---
reason="$(tmux_pane_gate_refusal "${other}" '❯')"; rc=$?
check "gate_refusal on a gone pane: prose" "no such pane" "${reason}"
check "gate_refusal on a gone pane: code" 75 "${rc}"
tmux set-option -p -t "${pane}" -u @ari_driving
reason="$(tmux_pane_gate_refusal "${pane}" '❯')"; rc=$?
check "gate_refusal not opted in: prose" "not opted in; Ari runs 'ari-driving on' in that pane" "${reason}"
check "gate_refusal not opted in: code" 77 "${rc}"
tmux set-option -p -t "${pane}" @ari_driving on
reason="$(tmux_pane_gate_refusal "${pane}" '❯')"; rc=$?
check "gate_refusal on an idle pane: silent, 0" "|0" "${reason}|${rc}"
check "every kind is in ARI_DRIVING_GATE_KINDS" "not_opted_in pane_gone copy_mode synchronized not_a_shell not_at_prompt" "${ARI_DRIVING_GATE_KINDS}"

# --- the lock terminates ---
(( EUID == 0 )) && print -- "note: running as root; permission-based lock cases are skipped"
with_deadline() {   # <seconds> <function> [args]: print the function's output and rc, or DEADLINE if it hangs
  local limit="${1}"; shift
  ( "$@"; print -r -- "rc=$?" ) >"${T}/out" 2>"${T}/err" &
  local pid=$! waited=0
  while kill -0 "${pid}" 2>/dev/null && (( waited < limit * 10 )); do sleep 0.1; (( waited += 1 )); done
  if kill -0 "${pid}" 2>/dev/null; then kill -9 "${pid}" 2>/dev/null; print -r -- DEADLINE; return; fi
  wait "${pid}" 2>/dev/null; cat "${T}/out"
}

ARI_DRIVING_LOCK_ROOT="${T}/locks"
check "a free lock is taken" "rc=0" "$(with_deadline 5 tmux_pane_lock %77 1)"
check "a held lock times out with 1" "rc=1" "$(with_deadline 5 tmux_pane_lock %77 1)"
tmux_pane_unlock %77

dir="$(tmux_pane_lock_dir %78)"
mkdir -p "${dir}"; print 0 > "${dir}/at"
check "a stale lock is broken and taken" "rc=0" "$(with_deadline 5 tmux_pane_lock %78 1)"
tmux_pane_unlock %78

dir="$(tmux_pane_lock_dir %79)"
mkdir -p "${dir}/blocker/inner"; print x > "${dir}/blocker/inner/f"; print 0 > "${dir}/at"
chmod 000 "${dir}/blocker"
check "a stale lock that will not break fails with LOCK_UNAVAILABLE, no loop" "rc=${ARI_DRIVING_EXIT_LOCK_UNAVAILABLE}" "$(with_deadline 5 tmux_pane_lock %79 1)"
contains "  ... and says so on stderr" "cannot be broken" "$(<"${T}/err")"
chmod -R u+rwx "${dir}"; rm -rf "${dir}"

print x > "${T}/file"
ARI_DRIVING_LOCK_ROOT="${T}/file/locks"
check "a lock root under a plain file fails with LOCK_UNAVAILABLE" "rc=${ARI_DRIVING_EXIT_LOCK_UNAVAILABLE}" "$(with_deadline 5 tmux_pane_lock %80 1)"
contains "  ... and names the root on stderr" "not a writable directory" "$(<"${T}/err")"

mkdir -p "${T}/ro"; chmod 500 "${T}/ro"
ARI_DRIVING_LOCK_ROOT="${T}/ro"
check "a read-only lock root fails with LOCK_UNAVAILABLE" "rc=${ARI_DRIVING_EXIT_LOCK_UNAVAILABLE}" "$(with_deadline 5 tmux_pane_lock %81 1)"
chmod 700 "${T}/ro"

print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
