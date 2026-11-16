# Tests for log.zsh, whose line format the bins, the dotfiles harness and the tests parse:
# `[TAG] [<ts>] [<caller>] message | key='value'` on stderr, nothing on stdout. Each case runs in a
# fresh `zsh -f` with stderr to a file, so stderr is not a terminal, as under launchd or a pipe.
# Only runs when OTTO_TEST__ZSH_PLUGINS_LOG=true
[[ "$OTTO_TEST__ZSH_PLUGINS_LOG" == "true" ]] || return 0

local _pass=0 _fail=0
local _lib="${${(%):-%x}:A:h}/log.zsh"
local _dir; _dir="$(mktemp -d "${TMPDIR:-/tmp}/log-test.XXXXXX")"
trap 'rm -rf "${_dir}"' EXIT

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then print -r -- "PASS: ${name}"; ((_pass++))
  else print -r -- "FAIL: ${name}"; print -r -- "  expected: ${expected}"; print -r -- "  actual:   ${actual}"; ((_fail++)); fi
}
function _m() {   # <name> <pattern> <actual>: a zsh pattern match
  if [[ "$3" == ${~2} ]]; then print -r -- "PASS: $1"; ((_pass++))
  else print -r -- "FAIL: $1"; print -r -- "  pattern: $2"; print -r -- "  actual:  $3"; ((_fail++)); fi
}

# _run [VAR=value ...] -- <zsh code>: run the code after sourcing the lib; sets _out and _err.
local _out _err _rc
function _run() {
  local -a envs=()
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  _rc=0
  _out="$(env -u LOG_PREAMBLE -u OTTO_NO_PREAMBLE -u VERBOSE -u OTTO_DEBUG -u OTTO_ERR_LOGFILE -u NO_COLOR "${envs[@]}" \
    zsh -f -c "source ${(q)_lib}; $1" 2>"${_dir}/err")" || _rc=$?
  _err="$(<"${_dir}/err")"
}

local TS='\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9](#c9)Z\]'
setopt extendedglob

# ── the line ──
_run -- 'f() { log::info "Pushing | repo='\''x'\''"; }; f'
_m "format: tag, timestamp, caller, message off a terminal" "\[INFO\] ${TS} \[f\] Pushing \| repo='x'" "${_err}"
_t "format: nothing on stdout" "" "${_out}"
_run LOG_PREAMBLE=0 -- 'log::info "hi"'
_t "LOG_PREAMBLE=0: the bare tag and message" "[INFO] hi" "${_err}"
_run OTTO_NO_PREAMBLE=1 LOG_PREAMBLE=1 -- 'log::info "hi"'
_t "OTTO_NO_PREAMBLE wins over LOG_PREAMBLE" "[INFO] hi" "${_err}"
_run LOG_PREAMBLE=0 -- 'log::ok a; log::warn b; log::dev c; log::err d'
_t "tiers: OK, WARN, DEV, ERROR" $'[OK] a\n[WARN] b\n[DEV] c\n[ERROR] d' "${_err}"
_run -- 'log::info "x"'
_t "colors: off when stderr is not a terminal" "no" "$([[ "${_err}" == *$'\e'* ]] && print yes || print no)"

# ── the caller ──
_run -- 'outer() { inner; }; inner() { log::info x; }; outer'
_m "caller: the function that logged" "\[INFO\] ${TS} \[inner\] x" "${_err}"
_run -- 'f() { run_cmd true; }; f'
_m "caller: run_cmd is skipped, its caller named" "\[INFO\] ${TS} \[f\] \| running \| cmd='true'" "${_err}"
_run -- 'f() { ns::_helper; }; ns::_helper() { log::info x; }; f'
_m "caller: a namespaced private helper (ns::_x) is skipped" "\[INFO\] ${TS} \[f\] x" "${_err}"

# ── debug ──
_run LOG_PREAMBLE=0 -- 'log::debug quiet'
_t "debug: off by default" "" "${_err}"
local v
for v in VERBOSE=true VERBOSE=1 OTTO_DEBUG=1; do
  _run LOG_PREAMBLE=0 "${v}" -- 'log::debug loud'
  _t "debug: on with ${v}" "[DEBUG] loud" "${_err}"
done
_run LOG_PREAMBLE=0 OTTO_DEBUG=0 -- 'log::debug quiet'
_t "debug: OTTO_DEBUG=0 is off" "" "${_err}"

# ── err ──
_run LOG_PREAMBLE=0 "OTTO_ERR_LOGFILE=${_dir}/errs" -- 'set -e; log::err "boom | k='\''v'\''"; print -r -- survived'
_t "err: returns 0 under set -e" "survived" "${_out}"
_t "err: OTTO_ERR_LOGFILE gets the bare message" "boom | k='v'" "$(<"${_dir}/errs")"

# ── multi-line tiers ──
_run LOG_PREAMBLE=0 -- 'log::INFO $'\''one\ntwo'\'''
_t "INFO: one line per input line, '| '-prefixed" $'[INFO] | one\n[INFO] | two' "${_err}"

# ── run_cmd ──
_run LOG_PREAMBLE=0 -- 'run_cmd sh -c "exit 3"; print -r -- "rc=$?"'
_t "run_cmd: returns the command's code" "rc=3" "${_out}"
_t "run_cmd: logs the run, then the failure with its code" $'[INFO] | running | cmd=\'sh -c exit 3\'\n[ERROR] | cmd failed | rc=\'3\' cmd=\'sh -c exit 3\'' "${_err}"
_run LOG_PREAMBLE=0 -- 'lvl=DEBUG run_cmd true'
_t "run_cmd: lvl=DEBUG keeps a quiet run quiet" "" "${_err}"
_run LOG_PREAMBLE=0 -- 'run_cmd_cap print -r -- hello'
_t "run_cmd_cap: logs the command's stdout" $'[INFO] | running | cmd=\'print -r -- hello\'\n[INFO] | hello' "${_err}"

# ── notifications ──
_run LOG_PREAMBLE=0 -- 'log::notify_image_check -title t -message m'
_t "notify_image_check: a post without -contentImage warns" "[WARN] notification without -contentImage | args='-title t -message m'" "${_err}"
_run LOG_PREAMBLE=0 -- "log::notify_image_check -title t -contentImage ${(q)_dir}/none.png"
_t "notify_image_check: an image that is not a file warns" "[WARN] notification -contentImage is not a file | path='${_dir}/none.png'" "${_err}"
_run LOG_PREAMBLE=0 -- 'log::notify_image_check -remove g'
_t "notify_image_check: -remove posts nothing and passes" "" "${_err}"

if (( _fail )); then print -r -- "log: ${_pass} passed, ${_fail} failed"; return 1; fi
print -r -- "log: all ${_pass} passed"
