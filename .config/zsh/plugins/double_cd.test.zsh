# Tests for double_cd.zsh. Fixture JSON in a scratch dir; both real tiers ignored; fzf and the
# after-cd hook are replaced, so nothing is listed or renamed.
# Only runs when OTTO_TEST__ZSH_PLUGINS_DOUBLE_CD=true
[[ "$OTTO_TEST__ZSH_PLUGINS_DOUBLE_CD" == "true" ]] || return 0

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

local _root; _root="$(mktemp -d "${TMPDIR:-/tmp}/double_cd_test.XXXXXX")"; _root="${_root:a}"
mkdir -p "${_root}/base/alpha" "${_root}/base/beta" "${_root}/cfg" "${_root}/r1" "${_root}/r2"
cat > "${_root}/cfg/a.json" <<EOF
[
  {"name": "zz", "dir": "${_root}/base", "text": "fixture base"},
  {"name": "bad name", "dir": "${_root}/base"},
  {"name": "zr", "dirs": ["${_root}/r1", "${_root}/r2"], "label": "fx", "text": "fixture repos"}
]
EOF
cat > "${_root}/cfg/b.json" <<EOF
[{"name": "zy", "dir": "~/nonexistent-double-cd-base"}]
EOF

export DOUBLE_CD_IGNORE_DIR_GLOBAL=1 DOUBLE_CD_IGNORE_DIR_LOCAL=1 DOUBLE_CD_DIRS="${_root}/cfg"
local _warn
_warn="$(source "${HOME}/.config/zsh/plugins/double_cd.zsh" 2>&1)"
source "${HOME}/.config/zsh/plugins/double_cd.zsh" 2>/dev/null
function double_cd::_after_cd() { print -r -- "after:$*" }

_t "bad names are skipped with a warning" "1" "$(print -r -- "${_warn}" | grep -c "bad name")"
_t "files merge; commands defined" "czr: function czy: function czz: function" "$(whence -w czr czy czz | tr '\n' ' ' | sed 's/ $//')"
_t "dcd lists name, dir, text" "czz|${_root}/base|fixture base" "$(dcd | grep czz | awk '{print $1"|"$2"|"$3" "$4}')"
_t "kind recorded" "dir dirs" "${DOUBLE_CD_KIND[zz]} ${DOUBLE_CD_KIND[zr]}"

_t "exact subdir cds in" "${_root}/base/alpha|after:czz alpha" "$(czz alpha >/dev/null; print -rn -- "$PWD|"; czz alpha 2>/dev/null | tail -1)"
_t "--new creates and enters" "${_root}/base/gamma" "$(czz --new gamma >/dev/null 2>&1; print -rn -- "$PWD")"
_t "--new on an existing dir just enters" "1" "$(czz --new gamma 2>&1 >/dev/null | grep -c 'already exists')"
function double_cd::_fzf() { print -r -- beta }
_t "no arg: fzf picks" "${_root}/base/beta" "$(czz >/dev/null 2>&1; print -rn -- "$PWD")"
_t "query with no such subdir goes to fzf" "${_root}/base/beta" "$(czz nope >/dev/null 2>&1; print -rn -- "$PWD")"
function double_cd::_fzf() { print -r -- . }
_t "picking '.' lands on the base and hints --new" "${_root}/base|1" "$(cd /; czz 2>/tmp/dcd_err.$$ >/dev/null; print -rn -- "$PWD|"; grep -c -- '--new' /tmp/dcd_err.$$; rm -f /tmp/dcd_err.$$)"
function double_cd::_fzf() { return 130 }
_t "fzf cancel: rc 1, stays put" "1|/" "$(cd /; czz >/dev/null 2>&1; print -rn -- "$?|$PWD")"
_t "missing base: rc 1 with the dir named" "1" "$(czy 2>&1 >/dev/null | grep -c "Base dir is missing | cmd='czy'")"

# dirs shape delegates to `repo`
_t "czr N goes to the Nth checkout" "${_root}/r2" "$(czr 2 >/dev/null 2>&1; print -rn -- "$PWD")"
_t "czr with no arg cycles (from r2 wraps to r1)" "${_root}/r1" "$(cd "${_root}/r2"; czr >/dev/null 2>&1; print -rn -- "$PWD")"
_t "czr out-of-range N fails" "1" "$(czr 9 2>&1 >/dev/null | grep -c 'No such checkout')"

unset DOUBLE_CD_IGNORE_DIR_GLOBAL DOUBLE_CD_IGNORE_DIR_LOCAL DOUBLE_CD_DIRS
unfunction czz czy czr 2>/dev/null
rm -rf "${_root}"

if (( _fail == 0 )); then
  log::info "double_cd: all ${_pass} passed"
else
  log::err "double_cd: ${_pass} passed, ${_fail} failed"
  return 1
fi
