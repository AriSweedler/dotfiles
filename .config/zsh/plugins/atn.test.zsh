# Tests for ~/.config/bin/atn — the terminal-notifier logging shim: one line per call in the
# state log (post, remove, list, then the argv), rotated by size, then terminal-notifier exec'd
# with the same argv and its rc returned. Only runs when OTTO_TEST__ZSH_PLUGINS_ATN=true
[[ "$OTTO_TEST__ZSH_PLUGINS_ATN" == "true" ]] || return 0

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

# Fixture: a fake terminal-notifier first on PATH that records its argv and exits 7, and a
# throwaway state home for the log.
local atn="${HOME}/.config/bin/atn"
local tmp; tmp="$(mktemp -d)"
mkdir -p "${tmp}/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "${FAKE_OUT}"\nexit 7\n' > "${tmp}/bin/terminal-notifier"
chmod +x "${tmp}/bin/terminal-notifier"
local logfile="${tmp}/state/ari-terminal-notifier/atn.log"

# atn ARGS...: the shim under the fixture; rc in $rc.
local rc
function atn() {
  rc=0
  XDG_STATE_HOME="${tmp}/state" FAKE_OUT="${tmp}/real.out" PATH="${tmp}/bin:/usr/bin:/bin" "${atn}" "$@" || rc=$?
}

atn -title t -message 'hello world' -group g
_t "post: terminal-notifier's rc comes back" 7 "${rc}"
_t "post: terminal-notifier got the argv" "-title t -message hello world -group g" "$(<"${tmp}/real.out")"
local line; line="$(tail -n 1 "${logfile}")"
_t "post: logged as post, after a timestamp" post "${${(z)line}[3]}"
_t "post: the argv, quoted so the line replays" "-title t -message 'hello world' -group g" "${line#* * post }"
_t "post: the timestamp shape" 1 "$([[ "${line}" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ * ]] && echo 1 || echo 0)"

atn -remove g
_t "remove: passed through" 7 "${rc}"
line="$(tail -n 1 "${logfile}")"
_t "remove: logged as remove" "remove -remove g" "${line#* * }"

atn -list ALL
line="$(tail -n 1 "${logfile}")"
_t "list: logged as list" "list -list ALL" "${line#* * }"

_t "three calls, three lines" 3 "$(wc -l < "${logfile}" | tr -d ' ')"

# Rotation: a log at the size cap is shifted aside before the next line is written.
head -c $(( 512 * 1024 )) /dev/zero | tr '\0' x > "${logfile}"
atn -title t -message rotated -group g
_t "rotation: the full log became .bak.1" 1 "$([[ -s "${logfile}.bak.1" ]] && echo 1 || echo 0)"
_t "rotation: the new log holds only the new line" 1 "$(wc -l < "${logfile}" | tr -d ' ')"
_t "rotation: ... and it is the call that rotated" "post -title t -message rotated -group g" "${"$(<"${logfile}")"#* * }"

rm -rf "${tmp}"
unfunction atn

if (( _fail == 0 )); then
  log::info "atn tests: ${_pass} passed"
else
  log::err "atn tests: ${_fail} failed, ${_pass} passed"
  return 1
fi
