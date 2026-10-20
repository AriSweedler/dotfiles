# Tests for ~/.config/bin/terminal-notifier — the logging shim: one line per call in the state
# log (post, remove, list, then the argv), then the real binary exec'd with the same argv and
# its rc returned. Only runs when OTTO_TEST__ZSH_PLUGINS_TERMINAL_NOTIFIER=true
[[ "$OTTO_TEST__ZSH_PLUGINS_TERMINAL_NOTIFIER" == "true" ]] || return 0

source "${0:h}/log.zsh"

local _pass=0 _fail=0

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    log::info "PASS: ${name}"
    ((_pass++))
  else
    log::err "FAIL: ${name}"
    print "  expected: $(print -r -- "$expected" | cat -v)"
    print "  actual:   $(print -r -- "$actual" | cat -v)"
    ((_fail++))
  fi
}

# Fixture: a fake "real" terminal-notifier first on PATH that records its argv and exits 7, and
# a throwaway state home for the log.
local shim="${HOME}/.config/bin/terminal-notifier"
local tmp; tmp="$(mktemp -d)"
mkdir -p "${tmp}/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "${FAKE_OUT}"\nexit 7\n' > "${tmp}/bin/terminal-notifier"
chmod +x "${tmp}/bin/terminal-notifier"
local logfile="${tmp}/state/terminal-notifier/terminal-notifier.log"

# shim ARGS...: the shim under the fixture; rc in $rc.
local rc
function shim() {
  rc=0
  XDG_STATE_HOME="${tmp}/state" FAKE_OUT="${tmp}/real.out" PATH="${tmp}/bin:/usr/bin:/bin" "${shim}" "$@" || rc=$?
}

shim -title t -message 'hello world' -group g
_t "post: the real binary's rc comes back" 7 "${rc}"
_t "post: the real binary got the argv" "-title t -message hello world -group g" "$(<"${tmp}/real.out")"
local line; line="$(tail -n 1 "${logfile}")"
_t "post: logged as post, after a timestamp" post "${${(z)line}[3]}"
_t "post: the argv, quoted so the line replays" "-title t -message 'hello world' -group g" "${line#* * post }"
_t "post: the timestamp shape" 1 "$([[ "${line}" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ * ]] && echo 1 || echo 0)"

shim -remove g
_t "remove: passed through" 7 "${rc}"
line="$(tail -n 1 "${logfile}")"
_t "remove: logged as remove" "remove -remove g" "${line#* * }"

shim -list ALL
line="$(tail -n 1 "${logfile}")"
_t "list: logged as list" "list -list ALL" "${line#* * }"

_t "three calls, three lines" 3 "$(wc -l < "${logfile}" | tr -d ' ')"

rm -rf "${tmp}"
unfunction shim

if (( _fail == 0 )); then
  log::info "terminal_notifier tests: ${_pass} passed"
else
  log::err "terminal_notifier tests: ${_fail} failed, ${_pass} passed"
fi
