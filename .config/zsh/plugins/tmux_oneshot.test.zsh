# Tests for ~/.config/bin/tmux-oneshot — menu rendering, key recovery, arg
# assembly, autodismiss, error capture. Only runs when
# OTTO_TEST__ZSH_PLUGINS_TMUX_ONESHOT=true
[[ "$OTTO_TEST__ZSH_PLUGINS_TMUX_ONESHOT" == "true" ]] || return 0

source "${0:h}/log.zsh"

local _pass=0 _fail=0

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

# ---------------------------------------------------------------------------
# Fixture: source the script (the ZSH_EVAL_CONTEXT guard keeps main from
# running) and stub its interactive seams. Stub state lives in files because
# the seams get called inside $(...) subshells.
# ---------------------------------------------------------------------------
source "${HOME}/.config/bin/tmux-oneshot"

local _picks_file _typed_file _db
_picks_file="$(mktemp /tmp/tmux-oneshot-test-picks.XXXXX)"
_typed_file="$(mktemp /tmp/tmux-oneshot-test-typed.XXXXX)"
_db="$(mktemp /tmp/tmux-oneshot-test-db.XXXXX.json)"

function _set_picks() { printf '%s\n' "$@" > "${_picks_file}" }
function _set_typed() { printf '%s' "${1}" > "${_typed_file}" }

# Each _fzf call consumes one line of the picks file: "ESC" → rc 130 (esc),
# else grep -E the menu on stdin (multi-line matches emulate multiselect).
function tmux_oneshot::_fzf() {
  local pat rest
  pat="$(head -1 "${_picks_file}")"
  rest="$(tail -n +2 "${_picks_file}")"
  printf '%s\n' "${rest}" > "${_picks_file}"
  if [[ "${pat}" == "ESC" ]]; then
    cat > /dev/null
    return 130
  fi
  grep -E "${pat}"
}
function tmux_oneshot::_read_value() { cat "${_typed_file}" }
function tmux_oneshot::_hold_until_escape() { echo "HELD" }

# The menu line for 1-based row N, hidden index stripped.
function _menu_line() { tmux_oneshot::_menu | cut -f2- | sed -n "${1}p" }
# Run an entry by key (menu.name or 1-based index), like the CLI path does.
function _run_key() { tmux_oneshot::_run "$(tmux_oneshot::_index_or_die "${1}")" }

cat > "${_db}" << 'EOF'
[
  {"cmd": "echo plain"},
  {"pwd": "/private/tmp", "cmd": "echo", "description": "greeter",
   "flags": [{"flag": "-n", "type": "bool"}],
   "subcommands": [{"cmd": "assembled-in-$PWD"}]},
  {"cmd": "true", "autodismiss": true},
  {"cmd": "false", "autodismiss": true},
  {"cmd": "echo named-ran", "autodismiss": true,
   "menu": {"name": "My Name", "text": "searchable words"}},
  {"cmd": "echo text-only", "description": "desc", "menu": {"text": "just text"}},
  {"cmd": "echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  {"cmd": "echo hi | cat", "autodismiss": true}
]
EOF
export TMUX_ONESHOT_DB="${_db}"

# ---------------------------------------------------------------------------
# Menu rendering: one batch jq pass; name = menu.name // cmd; capped column
# ---------------------------------------------------------------------------
# Entry 7's name is 49 chars → capped at 40, so names pad to 42 (width + 2).
_t "menu hidden field is each entry's index" "0
1
2
3
4
5
6
7" "$(tmux_oneshot::_menu | cut -f1)"
_t "menuitem plain: cmd is the name, no body, no padding" \
  "echo plain" "$(_menu_line 1)"
_t "menuitem unnamed: body excludes cmd" \
  "${(r:42:):-echo}…  # greeter @ /private/tmp" "$(_menu_line 2)"
_t "menuitem named: menu.name + menu.text" \
  "${(r:42:):-My Name}searchable words" "$(_menu_line 5)"
_t "menuitem text-only: cmd as name, text overrides body" \
  "${(r:42:):-echo text-only}just text" "$(_menu_line 6)"
_t "long cmd truncates with ellipsis, never wraps" \
  "echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa…" "$(_menu_line 7)"
# Regression: a cmd containing " | " renders verbatim and runs (this class
# of line killed the popup under fzfdb's separator padding).
_t "pipe-in-cmd renders verbatim" "echo hi | cat" "$(_menu_line 8)"
_t "pipe-in-cmd runs" "hi" "$(_run_key 8 2>/dev/null)"

# ---------------------------------------------------------------------------
# Key resolution: name-or-index keys; unknown keys fail clean
# ---------------------------------------------------------------------------
_t "list mixes indices and names" "1
2
3
4
My Name
6
7
8" "$(tmux_oneshot::action::list)"

local _err_out _err_rc
_err_out="$(tmux_oneshot::_index_or_die bogus 2>&1)"; _err_rc=$?
_t "unknown key: rc 1" "1" "${_err_rc}"
_t "unknown key: clean error, no jq --argjson blowup" "" "$(print -r -- "${_err_out}" | grep -i argjson)"
_t "unknown key: names the key" "Unknown key" "$(print -r -- "${_err_out}" | grep -o 'Unknown key')"

# The preview is one jq on the hidden index — resolve "My Name"'s row.
_t "preview jq resolves a hidden index to its entry" "echo named-ran" \
  "$(jq -r --argjson i "$(tmux_oneshot::_menu | grep -F 'My Name' | cut -f1)" '.[$i].cmd' "${TMUX_ONESHOT_DB}")"

# ---------------------------------------------------------------------------
# Render styles (pure)
# ---------------------------------------------------------------------------
_t "style space"         "--f v"     "$(tmux_oneshot::_render_kv --f space v)"
_t "style space-quoted"  "--f 'v'"   "$(tmux_oneshot::_render_kv --f space-quoted v)"
_t "style equals"        "--f=v"     "$(tmux_oneshot::_render_kv --f equals v)"
_t "style equals-quoted" "--f='v'"   "$(tmux_oneshot::_render_kv --f equals-quoted v)"
_t "quote escaping"      "--f='it'\\''s'" "$(tmux_oneshot::_render_kv --f equals-quoted "it's")"
tmux_oneshot::_render_kv --f bogus v &>/dev/null
_t "unknown style rc" "1" "$?"

# ---------------------------------------------------------------------------
# Assembly: flags multiselect, kv values, subcommand recursion
# ---------------------------------------------------------------------------
local _entry='{"cmd": "mycmd", "flags": [
  {"flag": "--verbose"},
  {"flag": "--dry-run", "type": "bool"},
  {"flag": "--env", "type": "kv", "style": "equals", "options": ["alpha", "prod"]},
  {"flag": "--msg", "type": "kv", "style": "equals-quoted"}
]}'
_t "plain cmd, no args" "echo hi" "$(tmux_oneshot::_assemble '{"cmd": "echo hi"}')"
_set_picks "verbose|dry-run"
_t "bool flags multiselect" "mycmd --verbose --dry-run" "$(tmux_oneshot::_assemble "${_entry}")"
_set_picks "env" "alpha"
_t "kv flag with options" "mycmd --env=alpha" "$(tmux_oneshot::_assemble "${_entry}")"
_set_picks "msg"; _set_typed "hello world"
_t "kv flag free-text quoted" "mycmd --msg='hello world'" "$(tmux_oneshot::_assemble "${_entry}" 2>/dev/null)"
_set_picks "ESC"
_t "esc on flags = no flags" "mycmd" "$(tmux_oneshot::_assemble "${_entry}")"
_set_picks "msg"; _set_typed ""
_t "empty typed value skips flag" "mycmd" "$(tmux_oneshot::_assemble "${_entry}" 2>/dev/null)"

local _nested='{"cmd": "irun", "flags": [
  {"flag": "ACTION", "type": "kv", "style": "equals", "options": ["copy_env", "login"]}
], "subcommands": [
  {"cmd": "ap", "description": "hyperbase all envs"},
  {"cmd": "git", "description": "deep demo", "subcommands": [
    {"cmd": "commit", "flags": [{"flag": "--amend"}]}
  ]}
]}'
_set_picks "ACTION" "login" "ap"
_t "flags + subcommand" "irun ACTION=login ap" "$(tmux_oneshot::_assemble "${_nested}")"
_set_picks "ESC" "git" "commit" "amend"
_t "two-level recursion" "irun git commit --amend" "$(tmux_oneshot::_assemble "${_nested}")"
_set_picks "ESC" "ESC"
tmux_oneshot::_assemble "${_nested}" > /dev/null 2>&1
_t "esc on subcommand aborts" "1" "$?"

# ---------------------------------------------------------------------------
# _run end-to-end: cwd, eval, hold-vs-autodismiss
# ---------------------------------------------------------------------------
_set_picks "ESC" "assembled"
_t "run e2e (cwd + eval)" "assembled-in-/private/tmp" \
  "$(_run_key 2 2>/dev/null | grep assembled-in)"
_t "default holds until esc" "HELD" \
  "$(_run_key 1 2>/dev/null | grep HELD)"
_t "autodismiss skips hold" "" \
  "$(_run_key 3 2>/dev/null | grep HELD)"
_t "failure holds despite autodismiss" "HELD" \
  "$(_run_key 4 2>/dev/null | grep HELD)"

# ---------------------------------------------------------------------------
# --debug: the non-interactive diagnostic passes on a healthy db
# ---------------------------------------------------------------------------
tmux_oneshot::action::debug > /dev/null 2>&1
_t "debug mode clean on healthy db" "0" "$?"

# ---------------------------------------------------------------------------
# Error capture: executed runs persist stderr to TMUX_ONESHOT_LOG (rotated
# per run), so popup errors survive the popup closing.
# ---------------------------------------------------------------------------
local _log_dir _log
_log_dir="$(mktemp -d /tmp/tmux-oneshot-test-log.XXXXX)"
_log="${_log_dir}/log.txt"
export TMUX_ONESHOT_LOG="${_log}"

# Regression for the popup outage of 2026-08-19: a spaced key must survive
# the executed CLI path end to end.
_t "CLI select by spaced name" "named-ran" \
  "$(zsh "${HOME}/.config/bin/tmux-oneshot" "My Name" 2>/dev/null | grep -o named-ran)"

zsh "${HOME}/.config/bin/tmux-oneshot" --list > /dev/null 2>&1
_t "run logs its invocation header" "1" "$(grep -c 'tmux-oneshot --list' "${_log}")"
_t "run logs its exit code" "── exit rc=0" "$(grep '── exit' "${_log}")"

zsh "${HOME}/.config/bin/tmux-oneshot" bogus-key > /dev/null 2>&1
_t "failed run: rc 1 logged" "── exit rc=1" "$(grep '── exit' "${_log}")"
_t "failed run: stderr captured in log" "1" "$(grep -c 'Unknown key' "${_log}")"
_t "previous run rotated aside" "1" "$(grep -c 'tmux-oneshot --list' "${_log}.bak.1")"

_t "--log prints path and content without rotating" "1" \
  "$(zsh "${HOME}/.config/bin/tmux-oneshot" --log | grep -c 'Unknown key')"
_t "--log did not rotate" "── exit rc=1" "$(grep '── exit' "${_log}")"

unset TMUX_ONESHOT_LOG
rm -rf "${_log_dir}"

# ---------------------------------------------------------------------------
rm -f "${_picks_file}" "${_typed_file}" "${_db}"
print
if (( _fail > 0 )); then
  log::err "tmux_oneshot: ${_pass} passed, ${_fail} failed"
  return 1
fi
log::info "tmux_oneshot: all ${_pass} passed"
