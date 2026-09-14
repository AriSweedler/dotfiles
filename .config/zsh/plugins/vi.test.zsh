# Tests for vi.zsh. Fake editors are defined here; no editor is launched and the real oneshot
# state dir is never written (XDG_STATE_HOME points at a scratch dir).
# Only runs when OTTO_TEST__ZSH_PLUGINS_VI=true
[[ "$OTTO_TEST__ZSH_PLUGINS_VI" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"

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

local _root; _root="$(mktemp -d "${TMPDIR:-/tmp}/vi_test.XXXXXX")"
local _saved_state="${XDG_STATE_HOME:-}"
export XDG_STATE_HOME="${_root}/state"
source "${HOME}/.config/zsh/plugins/vi.zsh"

# The real family is loaded in this shell too (run_tests sources the plugin dir when interactive),
# so every assertion filters to the zz fakes.
local _hit="${_root}/hit"
function vi_::zz_alpha() { print -r -- "alpha" >> "${_hit}" }
alias vi_zza=vi_::zz_alpha
function vi_::zz_beta() { print -r -- "beta" >> "${_hit}" }
alias vi_zzb=vi_::zz_beta

_t "editors: short and long from the aliases" $'zza\tzz_alpha\nzzb\tzz_beta' "$(vi_::_editors | grep zz_)"
_t "list: alias column then function" "  vi_zza           zz_alpha" "$(vi_::_list | grep 'vi_zza')"
_t "verify: clean family passes" "0" "$(vi_::_verify >/dev/null 2>&1; print -rn -- $?)"

function vi_::_fzf() { print -r -- $'zzb\tzz_beta' }
: > "${_hit}"
_t "pick: runs the chosen editor" "beta" "$(vi_ >/dev/null 2>&1; cat "${_hit}")"
function vi_::_fzf() { return 130 }
_t "pick: cancel is rc 1, runs nothing" "1|" "$(: > "${_hit}"; vi_ >/dev/null 2>&1; print -rn -- "$?|$(cat "${_hit}")")"

_t "oneshot json: one vi/ row per editor, opens in window vi" \
  '{"menu":{"name":"vi/zza","text":"zz_alpha"},"cmd":"irun vi_zza","window":"vi"}' \
  "$(vi_::_oneshot_json | jq -c '.[] | select(.menu.name == "vi/zza")')"
vi_::_publish
_t "publish: writes the generated file" "1" "$(jq '[.[] | select(.menu.name == "vi/zzb")] | length' "${XDG_STATE_HOME}/tmux_oneshot/generated/vi.json")"
local _mtime1; _mtime1="$(stat -f %m "${VI_ONESHOT_FILE}")"
sleep 1; vi_::_publish
_t "publish: unchanged family leaves the file alone" "${_mtime1}" "$(stat -f %m "${VI_ONESHOT_FILE}")"

alias vi_zzbad=vi_::zz_missing
_t "verify: alias to a missing function fails" "1" "$(vi_::_verify 2>&1 >/dev/null | grep -c "missing function | alias='vi_zzbad'")"
unalias vi_zzbad
function vi_::zz_orphan() { : }
_t "verify: editor without an alias fails" "1" "$(vi_::_verify 2>&1 >/dev/null | grep -c "no vi_ alias | function='vi_::zz_orphan'")"
unfunction vi_::zz_orphan
alias vi_zzc=vi_::zz_alpha
_t "verify: two aliases for one editor fails" "1" "$(vi_::_verify 2>&1 >/dev/null | grep -c "several vi_ aliases | function='vi_::zz_alpha'")"
unalias vi_zzc
alias vi_zzold=v::something
_t "verify: alias outside the namespace fails" "1" "$(vi_::_verify 2>&1 >/dev/null | grep -c "must point at a vi_:: function | alias='vi_zzold'")"
unalias vi_zzold
_t "verify: machinery functions are not editors" "0" "$(vi_::_verify 2>&1 >/dev/null | grep -c 'vi_::_')"

unalias vi_zza vi_zzb
unfunction vi_::zz_alpha vi_::zz_beta
if [[ -n "${_saved_state}" ]]; then export XDG_STATE_HOME="${_saved_state}"; else unset XDG_STATE_HOME; fi
VI_ONESHOT_FILE="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux_oneshot/generated/vi.json"
rm -rf "${_root}"

if (( _fail == 0 )); then
  log::info "vi: all ${_pass} passed"
else
  log::err "vi: ${_pass} passed, ${_fail} failed"
  return 1
fi
