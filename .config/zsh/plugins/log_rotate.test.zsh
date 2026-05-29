# Tests for log_rotate.zsh — rotation, retention, parent-dir, bad input.
# Only runs when OTTO_TEST__ZSH_PLUGINS_LOG_ROTATE=true (sourced inside the
# plugin loader's function scope, like tmux.test.zsh, so top-level `local` is ok).
[[ "$OTTO_TEST__ZSH_PLUGINS_LOG_ROTATE" == "true" ]] || return 0

source "${0:h}/log.zsh"
source "${0:h}/log_rotate.zsh"

local _pass=0 _fail=0

function _t() {  # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ((_pass++)); log::info "ok   | $name"
  else
    ((_fail++)); log::err "FAIL | $name | expected='$expected' actual='$actual'"
  fi
}

# <missing> for absent files so assertions read clearly.
function _cat() { [[ -e "$1" ]] && cat "$1" || print -n "<missing>"; }

local TMP; TMP="$(mktemp -d /tmp/log_rotate.test.XXXXXX)"

# --- no-op when there's nothing to rotate yet -----------------------------
local LOG="${TMP}/d/log.txt"
log_rotate "${LOG}" 5
_t "noop: rc"          "0"          "$?"
_t "noop: dir created" "yes"        "$([[ -d "${TMP}/d" ]] && print yes || print no)"
_t "noop: no log"      "<missing>"  "$(_cat "${LOG}")"
_t "noop: no bak.1"    "<missing>"  "$(_cat "${LOG}.bak.1")"

# --- a "run" = rotate, then write fresh -----------------------------------
function _run() { log_rotate "${LOG}" "$1"; print -r -- "$2" > "${LOG}"; }

_run 5 r1
_t "r1: current"   "r1"         "$(_cat "${LOG}")"
_t "r1: no bak.1"  "<missing>"  "$(_cat "${LOG}.bak.1")"

_run 5 r2
_t "r2: current"   "r2"  "$(_cat "${LOG}")"
_t "r2: bak.1"     "r1"  "$(_cat "${LOG}.bak.1")"

# fill past keep=5: runs r3..r7, oldest (r1) dropped
_run 5 r3; _run 5 r4; _run 5 r5; _run 5 r6; _run 5 r7
_t "r7: current"      "r7"         "$(_cat "${LOG}")"
_t "r7: bak.1"        "r6"         "$(_cat "${LOG}.bak.1")"
_t "r7: bak.5"        "r2"         "$(_cat "${LOG}.bak.5")"
_t "r7: bak.6 absent" "<missing>"  "$(_cat "${LOG}.bak.6")"

# --- keep=2 retires faster ------------------------------------------------
local LOG2="${TMP}/e/log.txt"
function _run2() { log_rotate "${LOG2}" 2; print -r -- "$1" > "${LOG2}"; }
_run2 a; _run2 b; _run2 c; _run2 d
_t "keep2: current"      "d"          "$(_cat "${LOG2}")"
_t "keep2: bak.1"        "c"          "$(_cat "${LOG2}.bak.1")"
_t "keep2: bak.2"        "b"          "$(_cat "${LOG2}.bak.2")"
_t "keep2: bak.3 absent" "<missing>"  "$(_cat "${LOG2}.bak.3")"

# --- bad `keep` is rejected (non-zero, nothing moved) ---------------------
log_rotate "${LOG}" 0 2>/dev/null;   _t "keep=0 → rc"   "1" "$?"
log_rotate "${LOG}" abc 2>/dev/null; _t "keep=abc → rc" "1" "$?"
_t "bad keep didn't touch current" "r7" "$(_cat "${LOG}")"

rm -rf "${TMP}"

if (( _fail == 0 )); then
  log::info "log_rotate.test: all ${_pass} passed"
else
  log::err "log_rotate.test: ${_fail} FAILED, ${_pass} passed"
fi
