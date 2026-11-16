# Tests for colors.zsh: color::contrast picks the text color that reads on each 256-color background, and
# color::ize wraps stdin in those escapes.
# Only runs when OTTO_TEST__ZSH_PLUGINS_COLORS=true
[[ "$OTTO_TEST__ZSH_PLUGINS_COLORS" == "true" ]] || return 0

local _pass=0 _fail=0
local _plugins="${${(%):-%x}:A:h}"
source "${_plugins}/log.zsh"
source "${_plugins}/colors.zsh"
function _t() {
  if [[ "$2" == "$3" ]]; then log::info "PASS: $1"; ((_pass++))
  else log::err "FAIL: $1"; print -u2 "  expected: $2"; print -u2 "  actual:   $3"; ((_fail++)); fi
}
function _c() { color::contrast "$1"; print -r -- "${REPLY}"; }

_t "contrast: white text on black (0)" 15 "$(_c 0)"
_t "contrast: black text on the other 15 basic colors" "0 0 0" "$(_c 1) $(_c 8) $(_c 15)"
_t "contrast: white on the darkest two rows of the 6x6x6 cube" "15 15" "$(_c 16) $(_c 27)"
_t "contrast: black from the third row on" "0 0" "$(_c 28) $(_c 231)"
_t "contrast: white on the dark half of the grey ramp" "15 15" "$(_c 232) $(_c 243)"
_t "contrast: black on the light half" "0 0" "$(_c 244) $(_c 255)"
local _all=1 i
for i in {0..255}; do color::contrast "$i"; [[ "${REPLY}" == (0|15) ]] || _all=0; done
_t "contrast: every index gets 0 or 15" 1 "${_all}"

_t "ize: background, contrast foreground, the text, a reset" $'\e[48;5;196m\e[38;5;15mhi\e[0m' "$(print hi | color::ize 196)"
_t "ize: --padding goes both sides" $'\e[48;5;17m\e[38;5;15m  x  \e[0m' "$(print x | color::ize --color 17 --padding '  ')"
_t "ize: a trailing newline from the pipe is dropped, inner ones kept" $'\e[48;5;1m\e[38;5;0ma\nb\e[0m' "$(printf 'a\nb\n' | color::ize 1)"
print x | color::ize --bogus 1 2>/dev/null; _t "ize: an unknown flag is exit 1" 1 "$?"

if (( _fail )); then log::err "colors: ${_pass} passed, ${_fail} failed"; return 1; fi
log::info "colors: all ${_pass} passed"
