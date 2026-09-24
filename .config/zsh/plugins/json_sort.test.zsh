# Tests for json_sort.zsh. Everything runs on temp files; nothing in the dotfiles is rewritten.
# Only runs when OTTO_TEST__ZSH_PLUGINS_JSON_SORT=true
[[ "$OTTO_TEST__ZSH_PLUGINS_JSON_SORT" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/json_sort.zsh"
zmodload zsh/stat

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

local _dir _rc _out
_dir="$(mktemp -d /tmp/json-sort-test.XXXXX)"

local _canonical=$'{\n  "a": 1,\n  "b": {\n    "c": [\n      3,\n      1,\n      2\n    ],\n    "d": true\n  }\n}'
_t "stdin: keys sorted recursively, 2-space indent, arrays untouched" "${_canonical}" "$(print -r -- '{"b":{"d":true,"c":[3,1,2]},"a":1}' | json_sort)"
local _bytes
_bytes="$(print -r -- '{"b":1,"a":2}' | json_sort | od -An -c | tr -d ' \n')"
_t "stdin: output ends with exactly one newline" "ok" "$([[ "${_bytes}" == *'}\n' && "${_bytes}" != *'\n\n' ]] && echo ok || echo "bad: ${_bytes}")"
print -r -- '{"b":{"d":true,"c":[3,1,2]},"a":1}' > "${_dir}/in.json"
_t "file: same canonical form" "${_canonical}" "$(json_sort "${_dir}/in.json")"
_t "file: two files print in order (two top-level keys each)" "4" "$(json_sort "${_dir}/in.json" "${_dir}/in.json" | grep -c '^  "[ab]"')"
_t "indentation: JSON_SORT_INDENTATION=4" $'{\n    "a": 2,\n    "b": {\n        "c": 1\n    }\n}' "$(print -r -- '{"b":{"c":1},"a":2}' | JSON_SORT_INDENTATION=4 json_sort)"
_t "indentation: 0 keeps one value per line with no indent, keys still sorted" $'{\n"a": 2,\n"b": {\n"c": 1\n}\n}' "$(print -r -- '{"b":{"c":1},"a":2}' | JSON_SORT_INDENTATION=0 json_sort)"
_out="$(print -r -- '{}' | JSON_SORT_INDENTATION=9 json_sort 2>&1)"; _rc=$?
_t "indentation: 9 is outside jq's range, rc 1" "1" "${_rc}"
_t "indentation: bad value named" "1" "$(print -r -- "${_out}" | grep -c "Invalid indentation | JSON_SORT_INDENTATION='9' expected='an integer 0..7'")"
print -r -- '{}' | JSON_SORT_INDENTATION=two json_sort >/dev/null 2>&1; _rc=$?
_t "indentation: non-integer rc 1" "1" "${_rc}"
_t "arrays of objects: element order kept, keys inside sorted" $'[\n  {\n    "x": 2,\n    "y": 1\n  },\n  {\n    "a": 0\n  }\n]' "$(print -r -- '[{"y":1,"x":2},{"a":0}]' | json_sort)"
_t "\$-prefixed key sorts first" $'{\n  "$generated": "g",\n  "bindings": []\n}' "$(print -r -- '{"bindings":[],"$generated":"g"}' | json_sort)"

# in-place: a non-canonical file is rewritten; a canonical one is left alone (content and mtime).
print -r -- '{"b":1,"a":2}' > "${_dir}/ip.json"
_out="$(json_sort --in-place "${_dir}/ip.json" 2>&1)"; _rc=$?
_t "in-place: rc 0" "0" "${_rc}"
_t "in-place: file is canonical afterwards" $'{\n  "a": 2,\n  "b": 1\n}' "$(cat "${_dir}/ip.json")"
_t "in-place: logs changed=yes" "1" "$(print -r -- "${_out}" | grep -c "json sorted | file='${_dir}/ip.json' changed='yes'")"
_t "in-place: no temp file left behind" "ip.json" "$(ls "${_dir}" | grep '^ip' | tr '\n' ' ' | sed 's/ $//')"
local _mtime_before _mtime_after
touch -t 200001010000 "${_dir}/ip.json"
_mtime_before="$(zstat +mtime "${_dir}/ip.json")"
_out="$(json_sort --in-place "${_dir}/ip.json" 2>&1)"; _rc=$?
_mtime_after="$(zstat +mtime "${_dir}/ip.json")"
_t "in-place no-op: rc 0" "0" "${_rc}"
_t "in-place no-op: logs changed=no" "1" "$(print -r -- "${_out}" | grep -c "changed='no'")"
_t "in-place no-op: mtime untouched" "${_mtime_before}" "${_mtime_after}"
_t "in-place no-op: content untouched" $'{\n  "a": 2,\n  "b": 1\n}' "$(cat "${_dir}/ip.json")"
print -r -- '{"z":0}' > "${_dir}/two.json"
json_sort --in-place "${_dir}/ip.json" "${_dir}/two.json" >/dev/null 2>&1; _rc=$?
_t "in-place: several files, rc 0" "0" "${_rc}"

# errors
print -r -- '{"a":' > "${_dir}/bad.json"
_out="$(json_sort "${_dir}/bad.json" 2>&1)"; _rc=$?
_t "invalid JSON file: rc 1" "1" "${_rc}"
_t "invalid JSON file: names the file and carries jq's message" "1" "$(print -r -- "${_out}" | grep -c "Invalid JSON | file='${_dir}/bad.json' error='jq: .*error")"
_out="$(print -r -- 'nope' | json_sort 2>&1)"; _rc=$?
_t "invalid JSON stdin: rc 1, names <stdin>" "1" "$(print -r -- "${_out}" | grep -c "file='<stdin>'")"
cp "${_dir}/bad.json" "${_dir}/bad2.json"
json_sort --in-place "${_dir}/bad2.json" >/dev/null 2>&1; _rc=$?
_t "invalid JSON in-place: rc 1" "1" "${_rc}"
_t "invalid JSON in-place: file left as it was" '{"a":' "$(cat "${_dir}/bad2.json")"
_t "invalid JSON in-place: no temp file left behind" "bad2.json" "$(ls "${_dir}" | grep '^bad2' | tr '\n' ' ' | sed 's/ $//')"
json_sort "${_dir}/missing.json" >/dev/null 2>&1; _rc=$?
_t "missing file: rc 1" "1" "${_rc}"
json_sort --in-place >/dev/null 2>&1; _rc=$?
_t "--in-place without files: rc 1" "1" "${_rc}"
json_sort --bogus >/dev/null 2>&1; _rc=$?
_t "unknown flag: rc 1" "1" "${_rc}"
_t "help: prints usage" "1" "$(json_sort --help 2>&1 | grep -c '^json-sort — canonical JSON')"

rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "json_sort: all ${_pass} passed"
else
  log::err "json_sort: ${_pass} passed, ${_fail} failed"
  return 1
fi
