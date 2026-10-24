# Tests for starship_config_join in starship.zsh.
# Only runs when OTTO_TEST__ZSH_PLUGINS_STARSHIP=true
[[ "$OTTO_TEST__ZSH_PLUGINS_STARSHIP" == "true" ]] || return 0

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

# Source only the function: the plugin's last lines would export STARSHIP_CONFIG and run starship init.
eval "$(sed -n '/^function starship_config_join/,/^}/p' "${HOME}/.config/zsh/plugins/starship.zsh")"

local _dir _base _overlays _out _rc
_dir="$(mktemp -d /tmp/starship-test.XXXXX)"
_base="${_dir}/starship.toml" _overlays="${_dir}/overlays" _out="${_dir}/state/starship.toml"
mkdir -p "${_overlays}"
print -r -- $'[time]\ndisabled = false' > "${_base}"

starship_config_join "${_base}" "${_overlays}" "${_out}"
_t "no overlays: the base is used" "${_base}" "${REPLY}"
_t "no overlays: nothing is generated" "absent" "$([[ -e ${_out} ]] && print present || print absent)"

print -r -- $'[kubernetes]\ndisabled = false' > "${_overlays}/kubernetes.toml"
starship_config_join "${_base}" "${_overlays}" "${_out}"
_t "one overlay: the generated file is used" "${_out}" "${REPLY}"
_t "one overlay: base first, then the overlay" \
  $'[time]\ndisabled = false\n\n# --- '"${_overlays}/kubernetes.toml"$' ---\n[kubernetes]\ndisabled = false' "$(<"${_out}")"

# An unchanged join must not validate again: a python3 that fails proves it was never called.
function python3() { return 1 }
starship_config_join "${_base}" "${_overlays}" "${_out}"
_t "unchanged join: no revalidation, the generated file is used" "${_out}" "${REPLY}"
unfunction python3

print -r -- $'[time]\ndisabled = true' > "${_overlays}/time.toml"
local _before="$(<"${_out}")" _log
_log="$(starship_config_join "${_base}" "${_overlays}" "${_out}" 2>&1)"
starship_config_join "${_base}" "${_overlays}" "${_out}" 2>/dev/null
_rc=$?
_t "table in both tiers: returns non-zero" "1" "${_rc}"
_t "table in both tiers: falls back to the base" "${_base}" "${REPLY}"
_t "table in both tiers: the generated file is untouched" "${_before}" "$(<"${_out}")"
_t "table in both tiers: logs the TOML error" "1" "$(print -r -- "${_log}" | grep -c 'not valid TOML.*twice')"

rm -f "${_overlays}"/*.toml
starship_config_join "${_base}" "${_overlays}" "${_out}"
_t "overlays removed: back to the base" "${_base}" "${REPLY}"

rm -rf "${_dir}"
print "starship: ${_pass} passed, ${_fail} failed"
(( _fail == 0 ))
