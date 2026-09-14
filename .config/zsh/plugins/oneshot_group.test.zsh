# Tests for oneshot_group.zsh. Writes only under a scratch XDG_STATE_HOME.
# Only runs when OTTO_TEST__ZSH_PLUGINS_ONESHOT_GROUP=true
[[ "$OTTO_TEST__ZSH_PLUGINS_ONESHOT_GROUP" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/oneshot_group.zsh"

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

local _root; _root="$(mktemp -d "${TMPDIR:-/tmp}/oneshot_group_test.XXXXXX")"
local _saved_state="${XDG_STATE_HOME:-}"
export XDG_STATE_HOME="${_root}"
local _gen="${_root}/tmux_oneshot/generated"
ONESHOT_GROUP_PENDING=()

# An alias family: prefix qq, machinery target qq::_help, one alias equal to the prefix.
function qq::alpha() { : }
function qq::beta() { : }
function qq::_help() { : }
alias qqa=qq::alpha
alias qqb=qq::beta
alias qq=qq::alpha
alias 'qq?'=qq::_help
alias qqx=other::thing

oneshot_group::aliases qq qq --fn-prefix qq:: --window qqwin
_t "aliases: deferred until flush" "no" "$([[ -f "${_gen}/qq.json" ]] && echo yes || echo no)"
oneshot_group::flush
_t "aliases: one row per alias in the namespace, alias-sorted, leaf = alias minus prefix" "qq a b" \
  "$(jq -r '.[].menu.name | sub("^qq/"; "")' "${_gen}/qq.json" | paste -sd' ' -)"
_t "aliases: text is the target minus the fn prefix" "alpha" "$(jq -r '.[] | select(.menu.name == "qq/a") | .menu.text' "${_gen}/qq.json")"
_t "aliases: cmd runs the alias through irun" "irun qqb" "$(jq -r '.[] | select(.menu.name == "qq/b") | .cmd' "${_gen}/qq.json")"
_t "aliases: window applied, no autodismiss" "qqwin null" "$(jq -r '.[0] | "\(.window) \(.autodismiss)"' "${_gen}/qq.json")"
_t "aliases: machinery (P_*) and foreign targets are skipped" "0" \
  "$(jq '[.[] | select(.menu.name == "qq/?" or .menu.name == "qq/x")] | length' "${_gen}/qq.json")"

local _m1; _m1="$(stat -f %m "${_gen}/qq.json")"
sleep 1
oneshot_group::aliases qq qq --fn-prefix qq:: --window qqwin; oneshot_group::flush
_t "unchanged rows: the file is not rewritten" "${_m1}" "$(stat -f %m "${_gen}/qq.json")"
alias qqc=qq::beta
oneshot_group::aliases qq qq --fn-prefix qq:: --window qqwin; oneshot_group::flush
_t "changed rows: the file is rewritten" "4" "$(jq length "${_gen}/qq.json")"

oneshot_group::rows rr --autodismiss <<< $'one\tfirst thing\techo 1\ntwo\tsecond\techo 2'
oneshot_group::flush
_t "rows: general form, popup surface, autodismiss" \
  '{"menu":{"name":"rr/two","text":"second"},"cmd":"echo 2","autodismiss":true}' \
  "$(jq -c '.[1]' "${_gen}/rr.json")"
_t "rows: no window key when none given" "0" "$(jq '[.[] | select(.window)] | length' "${_gen}/rr.json")"
_t "rows: no header entry without --key or --text" "0" "$(jq '[.[] | select(.menu.name == "rr/")] | length' "${_gen}/rr.json")"
oneshot_group::rows ss --key ctrl-x --text 'the ss family' <<< $'one\tfirst\techo 1'
oneshot_group::flush
_t "--key/--text: header entry first, named <group>/" \
  '{"menu":{"name":"ss/","text":"the ss family"},"key":"ctrl-x"}' "$(jq -c '.[0]' "${_gen}/ss.json")"
_t "--key alone: header with key only" '{"menu":{"name":"tt/"},"key":"ctrl-x"}' \
  "$(oneshot_group::rows tt --key ctrl-x <<< $'a\tb\tc'; oneshot_group::flush; jq -c '.[0]' "${_gen}/tt.json")"
_t "unknown option: rc 1" "1" "$(oneshot_group::aliases zz zz --bogus 2>/dev/null; print -rn -- $?)"
_t "flush empties the queue" "0" "${#ONESHOT_GROUP_PENDING}"

unalias qqa qqb qq 'qq?' qqx qqc
unfunction qq::alpha qq::beta qq::_help
if [[ -n "${_saved_state}" ]]; then export XDG_STATE_HOME="${_saved_state}"; else unset XDG_STATE_HOME; fi
rm -rf "${_root}"

if (( _fail == 0 )); then
  log::info "oneshot_group: all ${_pass} passed"
else
  log::err "oneshot_group: ${_pass} passed, ${_fail} failed"
  return 1
fi
