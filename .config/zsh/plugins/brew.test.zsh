# Tests for brew.zsh. Sources it in a subshell and reads the environment a child process sees,
# which is all brew itself sees.
# Only runs when OTTO_TEST__ZSH_PLUGINS_BREW=true
[[ "$OTTO_TEST__ZSH_PLUGINS_BREW" == "true" ]] || return 0

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

local _var
for _var in HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK HOMEBREW_NO_INSTALL_CLEANUP; do
  _t "${_var} reaches a child process" "1" \
    "$( (unset "${_var}"; source "${HOME}/.config/zsh/plugins/brew.zsh" >/dev/null 2>&1; /usr/bin/env) | sed -n "s/^${_var}=//p")"
done

if (( _fail == 0 )); then
  log::info "brew: all ${_pass} passed"
else
  log::err "brew: ${_pass} passed, ${_fail} failed"
  return 1
fi
