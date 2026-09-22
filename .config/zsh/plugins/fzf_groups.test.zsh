# Tests for fzf_groups.zsh: spec validation, the rendered rows, key and row picks, the prompt
# option (editor stubbed), the selection JSON, and pick's exit codes with fzf stubbed.
# Only runs when OTTO_TEST__ZSH_PLUGINS_FZF_GROUPS=true
[[ "$OTTO_TEST__ZSH_PLUGINS_FZF_GROUPS" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/fzf_groups.zsh"

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

local _spec='{"groups":[
  {"name":"action","label":"action","default":"n","options":[
    {"key":"n","label":"next","value":"next"},
    {"key":"c","label":"current","value":"current"}]},
  {"name":"words","default":"5","options":[
    {"key":"5","label":"50 words","value":"--words 50"},
    {"key":"o","label":"other…","prompt":"words: ","value":"--words {}"}]}]}'

# --- validation ---
_t "sound spec passes" "" "$(fzf_groups::_validate "${_spec}")"
_t "no groups" "no groups" "$(fzf_groups::_validate '{"groups":[]}')"
_t "default not an option" "default is not an option key | group=a default=x" \
  "$(fzf_groups::_validate '{"groups":[{"name":"a","default":"x","options":[{"key":"y","label":"Y"}]}]}')"
_t "missing default" "group has no default | group=a" \
  "$(fzf_groups::_validate '{"groups":[{"name":"a","options":[{"key":"y","label":"Y"}]}]}')"
_t "key must be one letter or digit" "option key must be one letter or digit | key=ab" \
  "$(fzf_groups::_validate '{"groups":[{"name":"a","default":"ab","options":[{"key":"ab","label":"Y"}]}]}')"
_t "key used twice across groups" "option key used twice | key=n" \
  "$(fzf_groups::_validate '{"groups":[{"name":"a","default":"n","options":[{"key":"n","label":"A"}]},{"name":"b","default":"n","options":[{"key":"n","label":"B"}]}]}')"

# --- state, rows, picks ---
local _state; _state="$(mktemp "${TMPDIR:-/tmp}/fzf_groups_test.XXXXXX")"
jq -c '{spec: ., sel: ([.groups[] | {key: .name, value: .default}] | from_entries), typed: {}}' <<< "${_spec}" > "${_state}"

_t "rows: defaults marked, label column padded to the widest label" \
  $'action\tn\taction  ● [n] next\naction\tc\taction  ○ [c] current\nwords\t5\twords   ● [5] 50 words\nwords\to\twords   ○ [o] other…' \
  "$(fzf_groups::_render "${_state}")"
fzf_groups::_pick "${_state}" c
_t "a key selects within its group" '{"action":"c","words":"5"}' "$(jq -c .sel "${_state}")"
fzf_groups::_pick "${_state}" z
_t "an unknown key is ignored" '{"action":"c","words":"5"}' "$(jq -c .sel "${_state}")"
fzf_groups::_pick_row "${_state}" $'action\tn\taction  ○ [n] next'
_t "a row pick reads the key column" '{"action":"n","words":"5"}' "$(jq -c .sel "${_state}")"
fzf_groups::_pick_row "${_state}" 'no tabs here'
_t "a row without columns is ignored" '{"action":"n","words":"5"}' "$(jq -c .sel "${_state}")"

# --- prompt option: the editor is stubbed ---
local _editor_file; _editor_file="$(mktemp "${TMPDIR:-/tmp}/fzf_groups_test.XXXXXX")"
function fzf_groups::_editor() {
  print -r -- "prompt=${1} current=${2}" >> "${_editor_file}.calls"
  local answer; answer="$(cat "${_editor_file}")"
  [[ "${answer}" == "ESC" ]] && return 130
  print -r -- "${answer}"
}
print -n "ESC" > "${_editor_file}"; fzf_groups::_pick "${_state}" o
_t "esc at the prompt keeps the selection" '{"action":"n","words":"5"}' "$(jq -c .sel "${_state}")"
print -n "" > "${_editor_file}"; fzf_groups::_pick "${_state}" o
_t "an empty answer keeps the selection" '{"action":"n","words":"5"}' "$(jq -c .sel "${_state}")"
print -n "300" > "${_editor_file}"; fzf_groups::_pick "${_state}" o
_t "an answer selects the option and is kept" '{"sel":{"action":"n","words":"o"},"typed":{"o":"300"}}' \
  "$(jq -c '{sel, typed}' "${_state}")"
_t "the row shows the answer" $'words\to\twords   ● [o] other…: 300' "$(fzf_groups::_render "${_state}" | tail -1)"
print -n "ESC" > "${_editor_file}"; fzf_groups::_pick "${_state}" o
_t "the editor opens on the previous answer" "prompt=words:  current=300" "$(tail -1 "${_editor_file}.calls")"
_t "selection substitutes {} with the answer" '{"action":"next","words":"--words 300"}' "$(fzf_groups::_selection "${_state}")"

# --- pick: fzf stubbed; the stub drives the callbacks like fzf's bindings would ---
local _fzf_rc_file; _fzf_rc_file="$(mktemp "${TMPDIR:-/tmp}/fzf_groups_test.XXXXXX")"
function fzf_groups::_fzf() {
  cat > /dev/null
  local a state=""
  for a in "$@"; do [[ "$a" == *"render "* ]] && { state="${a##*render }"; state="${state%%)*}"; break; }; done
  [[ -n "${state}" ]] && fzf_groups::_pick "${(Q)state}" c
  return "$(cat "${_fzf_rc_file}")"
}
print -n 0 > "${_fzf_rc_file}"
_t "pick: alt-enter prints the selection" '{"action":"current","words":"--words 50"}' "$(fzf_groups::pick "${_spec}" --title t)"
print -n 130 > "${_fzf_rc_file}"
fzf_groups::pick "${_spec}" > /dev/null 2>&1
_t "pick: esc is back" "${FZF_GROUP_BACK_RC}" "$?"
print -n 2 > "${_fzf_rc_file}"
fzf_groups::pick "${_spec}" > /dev/null 2>&1
_t "pick: a broken fzf is rc 1" "1" "$?"
fzf_groups::pick '{"groups":[]}' > /dev/null 2>&1
_t "pick: a bad spec is rc 1" "1" "$?"
_t "pick: no state files left behind" "" "$(print -l -- "${TMPDIR:-/tmp}"/fzf_groups.??????(N))"

rm -f "${_state}" "${_state}.tmp" "${_editor_file}" "${_editor_file}.calls" "${_fzf_rc_file}"
if (( _fail == 0 )); then
  log::info "fzf_groups: all ${_pass} passed"
else
  log::err "fzf_groups: ${_pass} passed, ${_fail} failed"
  return 1
fi
