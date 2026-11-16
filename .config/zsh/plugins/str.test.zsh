# Tests for str.zsh: str::join and str::colorize take items from their arguments, or from stdin when
# none are given, and treat the separator and the text as data. Also .zshrc's prepend_to_path, a pure
# helper that lives there: it moves an entry to the front of PATH without a duplicate.
# Only runs when OTTO_TEST__ZSH_PLUGINS_STR=true
[[ "$OTTO_TEST__ZSH_PLUGINS_STR" == "true" ]] || return 0

local _pass=0 _fail=0
local _plugins="${${(%):-%x}:A:h}"
source "${_plugins}/log.zsh"
source "${_plugins}/str.zsh"
function _t() {
  if [[ "$2" == "$3" ]]; then log::info "PASS: $1"; ((_pass++))
  else log::err "FAIL: $1"; print -u2 "  expected: $2"; print -u2 "  actual:   $3"; ((_fail++)); fi
}

_t "join: arguments" "a, b, c" "$(str::join ', ' a b c </dev/null)"
_t "join: arguments win over a piped stdin" "a-b" "$(print -l x y | str::join - a b)"
_t "join: stdin's lines when no arguments" "x-y" "$(print -l x y | str::join -)"
_t "join: a '%' in the separator is printed as is" "a%sb" "$(str::join '%s' a b </dev/null)"
_t "join: a '%' in an item too" "100%|5%" "$(str::join '|' '100%' '5%' </dev/null)"
_t "join: one item, no separator" "solo" "$(str::join , solo </dev/null)"
_t "join: nothing to join prints nothing" "" "$(str::join , </dev/null)"
local _saved_red="${c_red}" _saved_rst="${c_rst}"
c_red=R c_rst=Z
_t "colorize: each argument on its own line" $'Ra%sZ\nRbZ' "$(str::colorize red 'a%s' b </dev/null)"
_t "colorize: stdin's lines when no arguments" $'RxZ\nRyZ' "$(print -l x y | str::colorize red)"
c_red="${_saved_red}" c_rst="${_saved_rst}"

# prepend_to_path, taken from .zshrc as written.
eval "$(awk '/^function prepend_to_path\(\) \{/,/^\}/' "${_plugins:h}/.zshrc")"
(( ${+functions[prepend_to_path]} )); _t "prepend_to_path: found in .zshrc" 0 "$?"
local -a path_before=("${path[@]}")
path=(/a /b /c)
prepend_to_path /b
_t "prepend_to_path: an entry already there moves to the front, once" "/b /a /c" "${path[*]}"
prepend_to_path /new
_t "prepend_to_path: a new entry goes in front" "/new /b /a /c" "${path[*]}"
prepend_to_path /new
_t "prepend_to_path: again changes nothing" "/new /b /a /c" "${path[*]}"
path=("${path_before[@]}")

if (( _fail )); then log::err "str: ${_pass} passed, ${_fail} failed"; return 1; fi
log::info "str: all ${_pass} passed"
