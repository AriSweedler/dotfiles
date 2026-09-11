# Tests for ~/.config/bin/repo. Fixture JSON and temp checkouts; a fake tmux on PATH records
# renames; `git ready` is never reached (hop from outside is tested with a fake git).
# Only runs when OTTO_TEST__ZSH_PLUGINS_REPO=true
[[ "$OTTO_TEST__ZSH_PLUGINS_REPO" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
local _repo="${HOME}/.config/bin/repo"

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

local _root; _root="$(mktemp -d "${TMPDIR:-/tmp}/repo_test.XXXXXX")"; _root="${_root:a}"
local _a="${_root}/a" _b="${_root}/b" _c="${_root}/c" _x="${_root}/x" _y="${_root}/y" _out="${_root}/out"
mkdir -p "${_a}/sub/deep" "${_b}" "${_c}" "${_x}" "${_y}" "${_out}" "${_root}/cfg" "${_root}/fakebin"
cat > "${_root}/cfg/sets.json" <<EOF
[
  {"name": "one", "dirs": ["${_a}", "${_b}", "${_c}"], "label": "fx"},
  {"name": "two", "dirs": ["${_x}", "${_y}"], "default": true}
]
EOF
cat > "${_root}/fakebin/tmux" <<EOF
#!/bin/sh
echo "\$*" >> "${_root}/tmux.log"
EOF
cat > "${_root}/fakebin/git" <<EOF
#!/bin/sh
echo "git \$* in \$PWD" >> "${_root}/git.log"
EOF
chmod +x "${_root}/fakebin/"*
export DOUBLE_CD_IGNORE_DIR_GLOBAL=1 DOUBLE_CD_IGNORE_DIR_LOCAL=1 DOUBLE_CD_DIRS="${_root}/cfg"
local _saved_tmux="${TMUX:-}"; unset TMUX

_t "index from first"      "1" "$(cd "${_a}" && "${_repo}" index)"
_t "index from a subdir"   "1" "$(cd "${_a}/sub/deep" && "${_repo}" index)"
_t "index from third"      "3" "$(cd "${_c}" && "${_repo}" index)"
_t "index picks the set containing PWD" "2" "$(cd "${_y}" && "${_repo}" index)"
_t "outside: default set is used" "0|${_x}" "$(cd "${_out}" && print -rn -- "$("${_repo}" index)|$("${_repo}" cycle)")"
_t "--set overrides" "${_a}" "$(cd "${_out}" && "${_repo}" cycle --set one)"
_t "cycle wraps" "${_a}" "$(cd "${_c}" && "${_repo}" cycle)"
_t "cycle from middle" "${_c}" "$(cd "${_b}" && "${_repo}" cycle)"
_t "list" "${_x}"$'\n'"${_y}" "$(cd / && "${_repo}" list --set two)"
_t "sets" "  one	fx	3 checkouts"$'\n'"  two	two	2 checkouts" "$("${_repo}" sets)"
_t "unknown set: rc 1" "1" "$(cd / && "${_repo}" cycle --set nine 2>&1 >/dev/null | grep -c "No such set | set='nine'")"

_t "rename outside tmux is silent rc 0" "0|" "$(cd "${_a}" && "${_repo}" rename 2>&1; print -rn -- "$?|")"
: > "${_root}/tmux.log"
_t "rename inside tmux labels label+index" "rename-window fx2" "$(cd "${_b}" && PATH="${_root}/fakebin:${PATH}" TMUX=fake "${_repo}" rename; cat "${_root}/tmux.log")"
: > "${_root}/tmux.log"
_t "rename with an unlabeled set uses the name" "rename-window two1" "$(cd "${_x}" && PATH="${_root}/fakebin:${PATH}" TMUX=fake "${_repo}" rename; cat "${_root}/tmux.log")"
_t "rename outside every set is silent" "" "$(cd "${_out}" && PATH="${_root}/fakebin:${PATH}" TMUX=fake "${_repo}" rename; cat "${_root}/tmux.log" | grep -v 'two1')"

_t "hop from inside prints the next checkout" "${_b}" "$(cd "${_a}" && "${_repo}" hop 2>/dev/null)"
: > "${_root}/git.log"
_t "hop from outside logs the jump and starts git ready in the destination" "${_x}|1|git ready in ${_x}" \
  "$(cd "${_out}" && out="$(PATH="${_root}/fakebin:${PATH}" "${_repo}" hop 2>"${_root}/err")"; for _ in {1..50}; do [[ -s "${_root}/git.log" ]] && break; sleep 0.1; done; print -rn -- "${out}|$(grep -c 'Jumping in' "${_root}/err")|$(cat "${_root}/git.log")")"
rm -rf "${_x}"
_t "hop into a missing checkout fails" "1" "$(cd "${_out}" && "${_repo}" hop 2>&1 >/dev/null | grep -c 'Checkout is missing')"

export DOUBLE_CD_DIRS="${_root}/empty"
mkdir -p "${_root}/empty"
_t "no sets: rc 1 and says where it looked" "1" "$(cd / && "${_repo}" cycle 2>&1 >/dev/null | grep -c 'No double_cd entry with dirs')"
_t "no sets: rename still silent rc 0" "0" "$(cd / && "${_repo}" rename >/dev/null 2>&1; print -rn -- $?)"
_t "help prints usage" "1" "$("${_repo}" --help | grep -c 'repo sets ')"

[[ -n "${_saved_tmux}" ]] && export TMUX="${_saved_tmux}"
unset DOUBLE_CD_IGNORE_DIR_GLOBAL DOUBLE_CD_IGNORE_DIR_LOCAL DOUBLE_CD_DIRS
rm -rf "${_root}"

if (( _fail == 0 )); then
  log::info "repo: all ${_pass} passed"
else
  log::err "repo: ${_pass} passed, ${_fail} failed"
  return 1
fi
