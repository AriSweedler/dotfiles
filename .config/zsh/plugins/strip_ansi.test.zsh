# Tests for ~/.config/bin/strip-ansi.
# Only runs when OTTO_TEST__ZSH_PLUGINS_STRIP_ANSI=true
[[ "$OTTO_TEST__ZSH_PLUGINS_STRIP_ANSI" == "true" ]] || return 0

local _pass=0 _fail=0
source "$HOME/.config/zsh/plugins/log.zsh"

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

local _bin="${HOME}/.config/bin/strip-ansi"
source "${HOME}/.config/zsh/plugins/strip_ansi.zsh"

# The function, in-process.
_t "strip_ansi function: color on and reset" "hello" "$(print -r -- $'\e[31mhello\e[0m' | strip_ansi)"
local _tee_file
_tee_file="$(mktemp /tmp/strip-ansi-test.XXXXX)"
: > "${_tee_file}"
_t "strip_ansi_tee: stderr keeps the colors" $'\e[31mred\e[0m' "$(print -r -- $'\e[31mred\e[0m' | strip_ansi_tee "${_tee_file}" 2>&1 >/dev/null)"
_t "strip_ansi_tee: the file is stripped and appended" "red" "$(cat "${_tee_file}")"
print -r -- $'\e[1mmore\e[0m' | strip_ansi_tee "${_tee_file}" 2>/dev/null
_t "strip_ansi_tee: appends, never truncates" $'red\nmore' "$(cat "${_tee_file}")"
rm -f "${_tee_file}"

# The wrapper script.

_t "color on and reset" "hello" "$(print -r -- $'\e[31mhello\e[0m' | "${_bin}")"
_t "bold+color with multiple params" "[ERROR] x" "$(print -r -- $'\e[1;35m[ERROR]\e[0m x' | "${_bin}")"
_t "256-color and truecolor" "ab" "$(print -r -- $'\e[38;5;208ma\e[38;2;10;20;30mb\e[m' | "${_bin}")"
_t "cursor and erase sequences" "line" "$(print -r -- $'\e[2K\e[1Gline\e[?25l' | "${_bin}")"
_t "plain text untouched" "no codes here | key='value'" "$(print -r -- "no codes here | key='value'" | "${_bin}")"
_t "empty lines preserved" $'a\n\nb' "$(print -r -- $'a\n\n\e[32mb\e[0m' | "${_bin}")"
_t "last line without newline is kept" "tail" "$(print -rn -- $'\e[33mtail' | "${_bin}")"
_t "brackets that are not escapes stay" "[INFO] a[1]" "$(print -r -- "[INFO] a[1]" | "${_bin}")"
_t "log.zsh output round-trips to its plain form" "[ERROR] boom | rc='1'" \
  "$(log::err "boom | rc='1'" 2>&1 | "${_bin}" | sed -E 's/ \[[0-9T:.Z-]+\] \[[^]]*\]//')"
_t "line count is preserved" "3" "$(print -r -- $'\e[1ma\e[0m\nb\n\e[2mc' | "${_bin}" | wc -l | tr -d ' ')"

if (( _fail == 0 )); then
  log::info "strip_ansi: all ${_pass} passed"
else
  log::err "strip_ansi: ${_pass} passed, ${_fail} failed"
  return 1
fi
