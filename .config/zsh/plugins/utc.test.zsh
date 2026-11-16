# Tests for utc.zsh: utc and timedelta parse ISO 8601 (a trailing Z allowed) and take their arguments as
# data, never as python source.
# Only runs when OTTO_TEST__ZSH_PLUGINS_UTC=true
[[ "$OTTO_TEST__ZSH_PLUGINS_UTC" == "true" ]] || return 0

local _pass=0 _fail=0
local _plugins="${${(%):-%x}:A:h}"
source "${_plugins}/log.zsh"
source "${_plugins}/utc.zsh"
function _t() {
  if [[ "$2" == "$3" ]]; then log::info "PASS: $1"; ((_pass++))
  else log::err "FAIL: $1"; print -u2 "  expected: $2"; print -u2 "  actual:   $3"; ((_fail++)); fi
}

_t "utc: a Z time in UTC" "UTC Time: ..... 2026-11-16 09:00:00+00:00" "$(TZ=America/Los_Angeles utc 2026-11-16T09:00:00Z | tail -n 1)"
_t "utc: and in local time" "Local Time: ... 2026-11-16 01:00:00-08:00" "$(TZ=America/Los_Angeles utc 2026-11-16T09:00:00Z | head -n 1)"
_t "utc: an offset time" "UTC Time: ..... 2026-11-16 09:00:00+00:00" "$(utc 2026-11-16T10:00:00+01:00 | tail -n 1)"
utc "x'); import os; os.system('touch ${TMPDIR:-/tmp}/utc-injected'); ('" >/dev/null 2>&1
_t "utc: a quote in the argument is data, not code" "no" "$([[ -e "${TMPDIR:-/tmp}/utc-injected" ]] && print yes || print no)"
rm -f "${TMPDIR:-/tmp}/utc-injected"
_t "timedelta: an hour" $'Time delta in seconds: 3600.0\nTime delta: 1:00:00' "$(timedelta 2026-11-16T08:00:00Z 2026-11-16T09:00:00Z)"
_t "timedelta: a later first time says so and prints the size" $'Negative delta\nTime delta in seconds: 90.0\nTime delta: 0:01:30' "$(timedelta 2026-11-16T09:01:30 2026-11-16T09:00:00)"
_t "timedelta: Z against an offset" "Time delta in seconds: 0.0" "$(timedelta 2026-11-16T09:00:00Z 2026-11-16T10:00:00+01:00 | head -n 1)"

if (( _fail )); then log::err "utc: ${_pass} passed, ${_fail} failed"; return 1; fi
log::info "utc: all ${_pass} passed"
