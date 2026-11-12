# Tests for open_any.zsh. Fake openers in a scratch dir, named by a scratch openers list, stand in
# for the one a switch writes, so no real opener is probed and nothing is opened.
# Only runs when OTTO_TEST__ZSH_PLUGINS_OPEN_ANY=true
[[ "$OTTO_TEST__ZSH_PLUGINS_OPEN_ANY" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/strip_ansi.zsh"
source "${HOME}/.config/zsh/plugins/open_any.zsh"

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

local _dir _hit
_dir="$(mktemp -d /tmp/open-any-test.XXXXX)"
_hit="${_dir}/hit"
# An opener that accepts text starting with its own kind and records an open.
function _fake_opener() {
  local kind="$1"
  cat > "${_dir}/open-${kind}" <<EOF
#!/usr/bin/env zsh
if [[ "\${1:-}" == --check ]]; then shift; [[ "\${1:-}" == ${kind}:* ]]; exit \$?; fi
print -r -- "${kind} \${1}" >> "${_hit}"
EOF
  chmod +x "${_dir}/open-${kind}"
}
_fake_opener alpha
_fake_opener beta
# Accepts alpha: too, to force an ambiguity.
cat > "${_dir}/open-greedy" <<EOF
#!/usr/bin/env zsh
if [[ "\${1:-}" == --check ]]; then shift; [[ "\${1:-}" == alpha:* || "\${1:-}" == greedy:* ]]; exit \$?; fi
print -r -- "greedy \${1}" >> "${_hit}"
EOF
chmod +x "${_dir}/open-greedy"
# Breaks rule 2: prints and exits 64.
cat > "${_dir}/open-broken" <<'EOF'
#!/usr/bin/env zsh
print "usage"; exit 64
EOF
chmod +x "${_dir}/open-broken"
: > "${_dir}/open-any"; chmod +x "${_dir}/open-any"

: > "${_dir}/open-off"   # listed, not executable
{
  local _o
  for _o in alpha any beta broken greedy off; do printf 'open-%s\t%s\n' "${_o}" "${_dir}/open-${_o}"; done
} > "${_dir}/openers"
export OPEN_ANY_LIST="${_dir}/openers" OPEN_ANY_PLUGIN_LIST="${_dir}/no-plugin-list"

_t "openers: the list's names, open-any and a non-executable left out" $'open-alpha\nopen-beta\nopen-broken\nopen-greedy' "$(open_any::openers)"
_t "path_of: the list's path" "${_dir}/open-beta" "$(open_any::path_of open-beta)"
_t "path_of: unlisted → rc 1" "1" "$(open_any::path_of open-nope >/dev/null; echo $?)"
_t "--list is the opener list" "$(open_any::openers)" "$(open_any --list)"

local _out _rc
: > "${_hit}"
_out="$(open_any 'beta:one' 2>&1)"; _rc=$?
_t "one match: dispatches to it" "beta beta:one" "$(cat "${_hit}")"
_t "one match: rc 0" "0" "${_rc}"
_t "one match: logs the opener" "Dispatching | opener='open-beta' text='beta:one'" "$(print -r -- "${_out}" | strip_ansi 2>/dev/null | sed -E 's/^.*\] //' | head -1)"

: > "${_hit}"
_out="$(open_any 'alpha:two' 2>&1)"; _rc=$?
_t "two matches: nothing opened" "" "$(cat "${_hit}")"
_t "two matches: rc 1" "1" "${_rc}"
_t "two matches: names both sides" "1" "$(print -r -- "${_out}" | grep -c "accepted='open-alpha, open-greedy' declined='open-beta, open-broken'")"

: > "${_hit}"
_out="$(open_any 'nobody wants this' 2>&1)"; _rc=$?
_t "zero matches: nothing opened" "" "$(cat "${_hit}")"
_t "zero matches: rc 1" "1" "${_rc}"
_t "zero matches: says what was asked" "1" "$(print -r -- "${_out}" | grep -c "No opener accepts this, nothing opened | text='nobody wants this' asked='open-alpha, open-beta, open-broken, open-greedy'")"

_t "snippet: newlines flattened and cut at 60" "a b $(printf 'x%.0s' {1..56})" "$(open_any::snippet $'a\nb '"$(printf 'x%.0s' {1..80})")"
_t "input_text: explicit arg wins" "given" "$(open_any::input_text given)"

# In-process probing: a loaded open_<kind> function shadows the script.
function open_alpha() { [[ "${1:-}" == --check ]] && return 1; print -r -- "fn ${2}" >> "${_hit}"; }
: > "${_hit}"
_out="$(open_any 'alpha:three' 2>&1)"; _rc=$?
_t "run: loaded function is probed instead of the script (alpha declines, greedy wins)" "greedy alpha:three" "$(cat "${_hit}")"
unfunction open_alpha

_out="$(open_any --verify 2>&1)"; _rc=$?
_t "verify: fails when an opener breaks the contract" "1" "${_rc}"
_t "verify: names the rule-2 offender once per probe text" "3" "$(print -r -- "${_out}" | grep -c "breaks the --check contract, rule 2 | opener='open-broken'")"
_t "verify: names the rule-5 offenders" "4" "$(print -r -- "${_out}" | grep -c "breaks rule 5")"

# The opener plugins come from the zsh plugin list: only its open_*.zsh lines are sourced.
mkdir -p "${_dir}/plugins"
print -r -- 'function open_beta() { print -r -- loaded-beta; }' > "${_dir}/plugins/open_beta.zsh"
print -r -- 'function not_an_opener() { :; }' > "${_dir}/plugins/other.zsh"
printf 'source_file %s\nsource_file %s\n' "${_dir}/plugins/other.zsh" "${_dir}/plugins/open_beta.zsh" > "${_dir}/plugin-list"
_t "load_plugins: sources the list's open_*.zsh" "loaded-beta" \
  "$(OPEN_ANY_PLUGIN_LIST="${_dir}/plugin-list"; open_any::load_plugins; open_beta)"
_t "load_plugins: and nothing else" "0" \
  "$(OPEN_ANY_PLUGIN_LIST="${_dir}/plugin-list"; open_any::load_plugins; (( ${+functions[not_an_opener]} )) && print 1 || print 0)"

rm -f "${_dir}/open-broken"
export OPEN_ANY_LIST="/nonexistent-open-any-list"
_out="$(open_any 'x' 2>&1)"; _rc=$?
_t "no openers: rc 1 and names the list" "1" "$(print -r -- "${_out}" | grep -c "No openers listed, nothing opened | list='/nonexistent-open-any-list'")"

unset OPEN_ANY_LIST OPEN_ANY_PLUGIN_LIST
rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "open_any: all ${_pass} passed"
else
  log::err "open_any: ${_pass} passed, ${_fail} failed"
  return 1
fi
