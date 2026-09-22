# Tests for ~/.config/bin/tmux-oneshot — loading (global/local/extra dirs,
# index, collisions), menu rendering, key recovery, picker resolution, arg
# assembly, run modes (hold/autodismiss/window/prompt), error capture. Only
# runs when OTTO_TEST__ZSH_PLUGINS_TMUX_ONESHOT=true
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
# Plain rows: the assertions read the menu text, not its colors.
TMUX_ONESHOT_KEY_STYLE=''
# CLI-run cases must not post real notifications or wait for a keypress on a real tty.
export TMUX_ONESHOT_NOTIFY=0 TMUX_ONESHOT_HOLD=0
# The run-mode tests below drive the in-popup eval path; the surface tests override per case.
export TMUX_ONESHOT_SURFACE=popup

local _picks_file _typed_file _calls_file _label_file _tmux_file _db
_picks_file="$(mktemp /tmp/tmux-oneshot-test-picks.XXXXX)"
_typed_file="$(mktemp /tmp/tmux-oneshot-test-typed.XXXXX)"
_calls_file="$(mktemp /tmp/tmux-oneshot-test-calls.XXXXX)"
_label_file="$(mktemp /tmp/tmux-oneshot-test-label.XXXXX)"
_tmux_file="$(mktemp /tmp/tmux-oneshot-test-tmux.XXXXX)"
_db="$(mktemp /tmp/tmux-oneshot-test-db.XXXXX.json)"

function _set_picks() { printf '%s\n' "$@" > "${_picks_file}" }
function _set_typed() { printf '%s' "${1}" > "${_typed_file}" }

# Each _fzf call appends its argv to _calls_file and consumes one line of the
# picks file: "ESC" → rc 130 (esc); a line with tabs speaks the picker's
# --print-query/--expect protocol, "QUERY<TAB>KEY<TAB>PATTERN" → prints QUERY,
# then KEY (only when argv carries --expect=), then grep -E PATTERN of the
# menu (empty PATTERN: consume stdin, rc 1 = zero matches); any other line is
# grep -E'd (multi-line matches emulate multiselect).
function tmux_oneshot::_fzf() {
  local pat rest
  print -r -- "$*" >> "${_calls_file}"
  pat="$(head -1 "${_picks_file}")"
  rest="$(tail -n +2 "${_picks_file}")"
  printf '%s\n' "${rest}" > "${_picks_file}"
  if [[ "${pat}" == "ESC" ]]; then
    cat > /dev/null
    return 130
  fi
  if [[ "${pat}" == *$'\t'* ]]; then
    local query key sel
    query="${pat%%$'\t'*}"; rest="${pat#*$'\t'}"; key="${rest%%$'\t'*}"; sel="${rest#*$'\t'}"
    print -r -- "${query}"
    [[ "$*" == *--expect=* ]] && print -r -- "${key}"
    if [[ -z "${sel}" ]]; then
      cat > /dev/null
      return 1
    fi
    grep -E "${sel}"
    return $?
  fi
  grep -E "${pat}"
}
# Records the prompt label so its wording is testable; answers from the typed file.
function tmux_oneshot::_read_value() { print -r -- "${1}" > "${_label_file}"; cat "${_typed_file}" }
function tmux_oneshot::_hold_until_escape() { echo "HELD" }
# The suite runs inside tmux: a real `tmux` here would flash the user's status
# line or open windows on the live server. Record argv joined by \x1f (a cmd
# with spaces or pipes stays one field) and do nothing.
function tmux() { print -r -- "${(pj:\x1f:)@}" >> "${_tmux_file}" }
# The last recorded tmux argv, fields <range> (cut syntax, default all), |-joined.
function _tmux_last() { tail -1 "${_tmux_file}" | cut -d $'\x1f' -f "${1:-1-}" | tr $'\x1f' '|' }

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

# Second DB: the AWS entries (§D) with the wrapper replaced by a stub script
# that echoes its argv — a df test must not read ldf data, and a PATH shim
# cannot intercept an absolute-path cmd — plus the keyed/window/prompt entries.
# `ap` deliberately carries a longer text than `apa` (ranking regression).
local _stub_dir _stub _db2
_stub_dir="$(mktemp -d /tmp/tmux-oneshot-test-stub.XXXXX)"
_stub="${_stub_dir}/aws_profile"
print -rl -- '#!/usr/bin/env zsh' 'print -r -- "aws_profile $*"' > "${_stub}"
chmod +x "${_stub}"
_db2="$(mktemp /tmp/tmux-oneshot-test-db2.XXXXX.json)"
jq --arg s "${_stub}" 'map(.cmd |= sub("STUB"; $s))' > "${_db2}" << 'EOF'
[
 {"menu": {"name": "ap",  "text": "AWS_PROFILE → clipboard · hyperbase, pick env (4)"}, "cmd": "STUB --query \"'hyperbase' \"", "autodismiss": true},
 {"menu": {"name": "aP",  "text": "AWS_PROFILE → clipboard · ALL accounts, pick (7)"},  "cmd": "STUB", "autodismiss": true},
 {"menu": {"name": "apa", "text": "hyperbase alpha"},      "cmd": "STUB --query \"'alpha' 'hyperbase' \"",      "autodismiss": true},
 {"menu": {"name": "aps", "text": "hyperbase staging"},    "cmd": "STUB --query \"'staging' 'hyperbase' \"",    "autodismiss": true},
 {"menu": {"name": "app", "text": "hyperbase production"}, "cmd": "STUB --query \"'production' 'hyperbase' \"", "autodismiss": true},
 {"menu": {"name": "aPa", "text": "all accounts · alpha"},   "cmd": "STUB --query \"'alpha' \"",   "autodismiss": true},
 {"menu": {"name": "aPs", "text": "all accounts · staging"}, "cmd": "STUB --query \"'staging' \"", "autodismiss": true},
 {"menu": {"name": "ap login", "text": "aws sso login · hyperbase, pick env → window sso"}, "window": "sso", "cmd": "ACTION=login STUB --query \"'hyperbase' \""},
 {"menu": {"name": "caffeinate", "text": "keep the display awake → window caf"}, "cmd": "echo caf-ran", "window": "caf", "key": "ctrl-k"},
 {"menu": {"name": "go", "text": "open a go/ link (prompts for the short name)"}, "prompt": "go/ ", "key": "ctrl-g", "cmd": "echo \"https://go/${ONESHOT_INPUT}\"", "autodismiss": true},
 {"menu": {"name": "claude-link", "text": "open the mermaid.ink URL on the clipboard"}, "key": "ctrl-l", "cmd": "echo link-ran", "autodismiss": true}
]
EOF

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
_t "preview: command line then the description, nothing else" $'\e[36mecho\e[0m\ngreeter' \
  "$(jq -r --arg i 1 "${TMUX_ONESHOT_JQ_PREVIEW}" "${TMUX_ONESHOT_DB}")"

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
_t "kv flag prompt label adds ' value: '" "--msg value: " "$(cat "${_label_file}")"
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
# Assembly: groups (the one-screen builder; fzf_groups::pick stubbed)
# ---------------------------------------------------------------------------
local _groups_file; _groups_file="$(mktemp /tmp/tmux-oneshot-test-groups.XXXXX)"
function fzf_groups::pick() {
  print -r -- "$*" >> "${_calls_file}"
  local answer; answer="$(cat "${_groups_file}")"
  [[ "${answer}" == "BACK" ]] && return "${FZF_GROUP_BACK_RC}"
  print -r -- "${answer}"
}
local _grouped='{"cmd": "typing", "menu": {"name": "typing"}, "groups": [
  {"name": "action", "default": "n", "options": [{"key": "n", "label": "next", "value": "next"}]},
  {"name": "words", "default": "5", "options": [{"key": "5", "label": "50", "value": "--words 50"}]}
], "flags": [{"flag": "--verbose"}]}'
print -n '{"action":"current","words":"--words 300"}' > "${_groups_file}"
_set_picks "verbose"
_t "groups: values in group order, before flags" "typing current --words 300 --verbose" \
  "$(tmux_oneshot::_assemble "${_grouped}")"
_t "groups: the screen gets the entry's spec and name" \
  '{"groups":[{"name":"action","default":"n","options":[{"key":"n","label":"next","value":"next"}]},{"name":"words","default":"5","options":[{"key":"5","label":"50","value":"--words 50"}]}]} --title typing --cmd typing' \
  "$(grep -- '--title typing' "${_calls_file}" | tail -1)"
print -n 'BACK' > "${_groups_file}"
tmux_oneshot::_assemble "${_grouped}" > /dev/null 2>&1
_t "groups: esc on the screen is back, not abort" "${FZF_GROUP_BACK_RC}" "$?"

# Through the picker: back reopens it, and without --select-1 so a one-entry list does not
# re-run the entry the user just left.
local _db_groups
_db_groups="$(mktemp /tmp/tmux-oneshot-test-db-groups.XXXXX)"
print -r -- "[${_grouped}]" > "${_db_groups}"
export TMUX_ONESHOT_DB="${_db_groups}"
: > "${_calls_file}"
_set_picks $'\t\ttyping' "ESC"
tmux_oneshot::_pick > /dev/null 2>&1
_t "groups: back from the screen returns to the picker, which then aborts on esc" "1" "$?"
_t "groups: the reopened picker passes --no-select-1" "1" \
  "$(grep -c -- '--no-select-1' "${_calls_file}")"
_t "groups: the first picker did not" "" "$(head -1 "${_calls_file}" | grep -o -- '--no-select-1')"
export TMUX_ONESHOT_DB="${_db}"
rm -f "${_groups_file}" "${_db_groups}"
unfunction fzf_groups::pick

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
: > "${_tmux_file}"
( export TMUX=test-dummy; _run_key 3 > /dev/null 2>&1 )
_t "autodismiss success flashes the entry name" "display-message|-d|1500|✓ true" "$(_tmux_last)"
: > "${_tmux_file}"
( unset TMUX; _run_key 3 > /dev/null 2>&1 )
_t "autodismiss outside tmux does not call tmux" "" "$(_tmux_last)"

# ---------------------------------------------------------------------------
# --debug: the non-interactive diagnostic passes on a healthy db
# ---------------------------------------------------------------------------
tmux_oneshot::action::debug > /dev/null 2>&1
_t "debug mode clean on healthy db" "0" "$?"

# ---------------------------------------------------------------------------
# Loading: global → local → TMUX_ONESHOT_DIRS, merged into an index under a
# temp XDG_STATE_HOME. TMUX_ONESHOT_DB is unset per case (the fixture's export
# is single-file mode) and re-exported at the end of the block.
# ---------------------------------------------------------------------------
local _xdg_c _xdg_d _xdg_s _extra1 _fake_home _editor
_xdg_c="$(mktemp -d /tmp/tmux-oneshot-test-xdgc.XXXXX)"
_xdg_d="$(mktemp -d /tmp/tmux-oneshot-test-xdgd.XXXXX)"
_xdg_s="$(mktemp -d /tmp/tmux-oneshot-test-xdgs.XXXXX)"
_extra1="$(mktemp -d /tmp/tmux-oneshot-test-extra1.XXXXX)"
_fake_home="$(mktemp -d /tmp/tmux-oneshot-test-home.XXXXX)"
local _saved_xdg_c="${XDG_CONFIG_HOME-}" _saved_xdg_d="${XDG_DATA_HOME-}" _saved_xdg_s="${XDG_STATE_HOME-}"
local _real_index="${_saved_xdg_s:-${HOME}/.local/state}/tmux_oneshot/index.json" _real_index_before=''
[[ -e "${_real_index}" ]] && _real_index_before="$(stat -f %m "${_real_index}")"
export XDG_CONFIG_HOME="${_xdg_c}" XDG_DATA_HOME="${_xdg_d}" XDG_STATE_HOME="${_xdg_s}"
local _index="${_xdg_s}/tmux_oneshot/index.json"
mkdir -p "${_xdg_c}/tmux_oneshot" "${_xdg_d}/tmux_oneshot" "${_fake_home}/oneshots"
_editor="${_xdg_s}/editor"
print -rl -- '#!/usr/bin/env zsh' 'print -rl -- "$@"' > "${_editor}"
chmod +x "${_editor}"

# g1/l1 share ctrl-k (key clash: l1 loses it); dup is defined in both tiers
# (shadow: local wins, keeps row 2).
cat > "${_xdg_c}/tmux_oneshot/macos.json" << 'EOF'
[
  {"menu": {"name": "g1", "text": "global one"}, "cmd": "echo g1", "key": "ctrl-k"},
  {"menu": {"name": "dup", "text": "global dup"}, "cmd": "echo global-dup"},
  {"menu": {"name": "g3", "text": "global three"}, "cmd": "echo g3"}
]
EOF
cat > "${_xdg_d}/tmux_oneshot/a.json" << 'EOF'
[
  {"menu": {"name": "l1", "text": "local one"}, "cmd": "echo l1", "key": "ctrl-k"},
  {"menu": {"name": "dup", "text": "local dup"}, "cmd": "echo local-dup"}
]
EOF
cat > "${_xdg_d}/tmux_oneshot/b.json" << 'EOF'
[
  {"menu": {"name": "l2", "text": "local two"}, "cmd": "echo l2", "key": "ctrl-g"}
]
EOF
echo '[{"menu": {"name": "x1"}, "cmd": "echo x1"}]' > "${_extra1}/x.json"
echo '[{"menu": {"name": "y1"}, "cmd": "echo y1"}]' > "${_fake_home}/oneshots/y.json"

# A fresh launch: no caller override, counters zeroed. Run inside $(...) or
# a subshell so the export _load performs never leaks into the suite.
function _fresh() {
  unset TMUX_ONESHOT_DB
  TMUX_ONESHOT_LOAD_SKIPPED=0 TMUX_ONESHOT_LOAD_SHADOWED=0 TMUX_ONESHOT_LOAD_KEYCLASH=0
  tmux_oneshot "$@"
}

_t "loads global then local, in file order" "g1
dup
g3
l1
l2" "$(_fresh --list 2>/dev/null)"
# Row 2 is dup, whose surviving definition is the local one.
_t "index carries each entry's tier" "global local global local local" "$(jq -r '[.[]._tier] | join(" ")' "${_index}")"
_t "index carries each entry's source file" "${_xdg_c}/tmux_oneshot/macos.json ${_xdg_d}/tmux_oneshot/a.json" \
  "$(jq -r '"\(.[0]._src) \(.[3]._src)"' "${_index}")"
_t "index written under XDG_STATE_HOME" "yes" "$([[ -f "${_index}" ]] && echo yes)"
_t "preview program: the command, colored; no description line when there is none" $'\e[36mecho g1\e[0m' \
  "$(jq -r --arg i 0 "${TMUX_ONESHOT_JQ_PREVIEW}" "${_index}")"
# The error must be ours alone: no mkdir or redirection message beside it.
chmod 555 "${_xdg_s}/tmux_oneshot"
_err_out="$(_fresh --list 2>&1 >/dev/null)"; _err_rc=$?
chmod 755 "${_xdg_s}/tmux_oneshot"
_t "read-only state dir: rc 1, exactly one error line" "1 1 Index dir not writable" \
  "${_err_rc} $(print -r -- "${_err_out}" | grep -c .) $(print -r -- "${_err_out}" | grep -o 'Index dir not writable')"
_t "TMUX_ONESHOT_DIRS appends in order and expands ~" "g1 dup g3 l1 l2 x1 y1" \
  "$(export HOME="${_fake_home}"; TMUX_ONESHOT_DIRS="${_extra1}:~/oneshots" _fresh --list 2>/dev/null | paste -sd' ' -)"
_t "TMUX_ONESHOT_DIRS entries are tier extra" "extra extra" "$(jq -r '"\(.[5]._tier) \(.[6]._tier)"' "${_index}")"
_err_out="$(TMUX_ONESHOT_DIRS="/nonexistent/oneshots:${_extra1}" _fresh --list 2>&1)"; _err_rc=$?
_t "missing TMUX_ONESHOT_DIRS dir: warns" "Oneshot dir missing" "$(print -r -- "${_err_out}" | grep -o 'Oneshot dir missing')"
_t "missing TMUX_ONESHOT_DIRS dir: skipped, rc 0" "0" "${_err_rc}"
_t "missing TMUX_ONESHOT_DIRS dir: siblings load" "x1" "$(print -r -- "${_err_out}" | grep -x x1)"
_t "IGNORE_DIR_GLOBAL skips global only" "l1 dup l2" \
  "$(TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 _fresh --list 2>/dev/null | paste -sd' ' -)"
_t "IGNORE_DIR_LOCAL skips local only" "g1 dup g3" \
  "$(TMUX_ONESHOT_IGNORE_DIR_LOCAL=1 _fresh --list 2>/dev/null | paste -sd' ' -)"
# The generated tier lives under XDG_STATE_HOME and loads after local.
mkdir -p "${_xdg_s}/tmux_oneshot/generated"
echo '[{"menu": {"name": "vi_/zz", "text": "zz_editor"}, "cmd": "irun vi_zz", "window": "vi_"}]' > "${_xdg_s}/tmux_oneshot/generated/vi_.json"
_t "generated tier loads after local" "g1 dup g3 l1 l2 vi_/zz" "$(_fresh --list 2>/dev/null | paste -sd' ' -)"
_t "generated tier is tagged generated" "generated" "$(jq -r '.[] | select(.menu.name == "vi_/zz") | ._tier' "${_index}")"
_t "IGNORE_DIR_GENERATED skips it" "g1 dup g3 l1 l2" \
  "$(TMUX_ONESHOT_IGNORE_DIR_GENERATED=1 _fresh --list 2>/dev/null | paste -sd' ' -)"
rm -rf "${_xdg_s}/tmux_oneshot/generated"
_t "--files lists tier and path for every file that would load" \
  "global	${_xdg_c}/tmux_oneshot/macos.json
local	${_xdg_d}/tmux_oneshot/a.json
local	${_xdg_d}/tmux_oneshot/b.json" "$(_fresh --files 2>/dev/null)"
_t "--files honors the ignore knobs" "1" "$(TMUX_ONESHOT_IGNORE_DIR_LOCAL=1 _fresh --files 2>/dev/null | wc -l | tr -d ' ')"
_t "unknown option: error plus help" "1 1" "$(_fresh --bogus 2>&1 >/dev/null | grep -c 'Unknown option') $(_fresh --bogus 2>&1 >/dev/null | grep -c 'Usage:')"
_t "tier is carried, not inferred from the path" "extra" \
  "$(mkdir -p "${_xdg_c}/extra_oneshots"; cp "${_extra1}/x.json" "${_xdg_c}/extra_oneshots/"; TMUX_ONESHOT_DIRS="${_xdg_c}/extra_oneshots" _fresh --list >/dev/null 2>&1; jq -r '.[-1]._tier' "${_index}")"

# Collisions: the merge keeps working; --debug reports and fails.
_err_out="$(_fresh --list 2>&1 >/dev/null)"
_t "duplicate name: later wins" "cmd=echo local-dup" "$(_fresh --dry-run dup 2>/dev/null | sed -n 2p)"
_t "duplicate name: keeps the first occurrence's row" "dup" "$(_fresh --list 2>/dev/null | sed -n 2p)"
_t "duplicate name: one warning" "1" "$(print -r -- "${_err_out}" | grep -c 'Shadowed oneshot')"
_t "duplicate name: warning names both sources" "kept='local:${_xdg_d}/tmux_oneshot/a.json' dropped='global:${_xdg_c}/tmux_oneshot/macos.json'" \
  "$(print -r -- "${_err_out}" | grep 'Shadowed oneshot' | grep -o "kept='[^']*' dropped='[^']*'")"
_t "duplicate key: later entry loses it" "null" "$(jq -r '.[] | select(.menu.name == "l1") | .key' "${_index}")"
_t "duplicate key: first keeps it" "ctrl-k" "$(jq -r '.[] | select(.menu.name == "g1") | .key' "${_index}")"
_t "duplicate key: error logged" "1" "$(print -r -- "${_err_out}" | grep -c 'Duplicate direct key dropped')"
_t "duplicate key: expect list has the key once" "ctrl-g,ctrl-k" "$(_fresh --debug 2>/dev/null | grep -o 'expect: *.*' | sed -E 's/^expect: *//')"
( _fresh --debug > /dev/null 2>&1 )
_t "--debug fails on shadow + key clash" "1" "$?"
_t "many files per dir load name-sorted" "a.json b.json" \
  "$(TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 _fresh --debug 2>/dev/null | grep -E '^  local' | cut -f3 | xargs -n1 basename | paste -sd' ' -)"
( TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 _fresh --debug > /dev/null 2>&1 )
_t "--debug clean on a healthy multi-file tree" "0" "$?"
_t "--debug lists one line per source" "local	2	${_xdg_d}/tmux_oneshot/a.json
local	1	${_xdg_d}/tmux_oneshot/b.json" \
  "$(TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 _fresh --debug 2>/dev/null | grep -E '^  (global|local|extra)' | sed 's/^  //')"

# One bad file must not hide its siblings.
echo '{}' > "${_xdg_d}/tmux_oneshot/c.json"
_err_out="$(_fresh --list 2>&1 >/dev/null)"
_t "bad file skipped: siblings load" "g1 dup g3 l1 l2" "$(_fresh --list 2>/dev/null | paste -sd' ' -)"
_t "bad file skipped: error names the file" "Skipping oneshot file: not a JSON list | path='${_xdg_d}/tmux_oneshot/c.json'" \
  "$(print -r -- "${_err_out}" | grep -o "Skipping oneshot file.*")"
_t "bad file skipped: _load rc 0, counter 1" "rc=0 skipped=1" \
  "$(unset TMUX_ONESHOT_DB; TMUX_ONESHOT_LOAD_SKIPPED=0; tmux_oneshot::_load 2>/dev/null; echo "rc=$? skipped=${TMUX_ONESHOT_LOAD_SKIPPED}")"
( TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 _fresh --debug > /dev/null 2>&1 )
_t "bad file skipped: --debug rc 1" "1" "$?"
rm -f "${_xdg_d}/tmux_oneshot/c.json"
mkdir -p "${_extra1}/allbad"
echo 'not json' > "${_extra1}/allbad/z.json"
_err_out="$(TMUX_ONESHOT_IGNORE_DIR_GLOBAL=1 TMUX_ONESHOT_IGNORE_DIR_LOCAL=1 TMUX_ONESHOT_DIRS="${_extra1}/allbad" _fresh --list 2>&1)"; _err_rc=$?
_t "all files bad: rc 1" "1" "${_err_rc}"
_t "all files bad: says so" "No loadable oneshot files" "$(print -r -- "${_err_out}" | grep -o 'No loadable oneshot files')"

# Single-file mode and seeding.
rm -f "${_index}"
_t "TMUX_ONESHOT_DB exported → single-file mode, no index" "rc=0 index=no" \
  "$(export TMUX_ONESHOT_DB="${_db}"; tmux_oneshot::_load; echo "rc=$? index=$([[ -e "${_index}" ]] && echo yes || echo no)")"
local _seed_c _seed_d
_seed_c="$(mktemp -d /tmp/tmux-oneshot-test-seedc.XXXXX)"
_seed_d="$(mktemp -d /tmp/tmux-oneshot-test-seedd.XXXXX)"
_t "zero files → seeds local commands.json" "1
hello world" "$(XDG_CONFIG_HOME="${_seed_c}" XDG_DATA_HOME="${_seed_d}" _fresh --list 2>/dev/null)"
_t "seed lands in the local dir" "yes" "$([[ -f "${_seed_d}/tmux_oneshot/commands.json" ]] && echo yes)"
_t "zero files with local ignored: no seed, rc 1" "1" \
  "$(XDG_CONFIG_HOME="${_seed_c}" XDG_DATA_HOME="${_seed_c}" TMUX_ONESHOT_IGNORE_DIR_LOCAL=1 _fresh --list >/dev/null 2>&1; echo $?)"
rm -rf "${_seed_c}" "${_seed_d}"

# --edit opens the defining file(s).
_t "--edit <local name> opens its file" "${_xdg_d}/tmux_oneshot/a.json" "$(EDITOR="${_editor}" _fresh --edit dup 2>/dev/null)"
_t "--edit <global name> opens its file" "${_xdg_c}/tmux_oneshot/macos.json" "$(EDITOR="${_editor}" _fresh --edit g1 2>/dev/null)"
_t "--edit opens every source, one per argument, in load order" "${_xdg_c}/tmux_oneshot/macos.json
${_xdg_d}/tmux_oneshot/a.json
${_xdg_d}/tmux_oneshot/b.json" "$(EDITOR="${_editor}" _fresh --edit 2>/dev/null)"
_t "--edit unknown name: rc 1" "1" "$(EDITOR="${_editor}" _fresh --edit nope >/dev/null 2>&1; echo $?)"

export XDG_CONFIG_HOME="${_saved_xdg_c}" XDG_DATA_HOME="${_saved_xdg_d}" XDG_STATE_HOME="${_saved_xdg_s}"
export TMUX_ONESHOT_DB="${_db}"
_t "real index untouched by the loading tests" "${_real_index_before}" \
  "$([[ -e "${_real_index}" ]] && stat -f %m "${_real_index}")"
_t "single-file --edit opens the DB itself" "${_db}" "$(EDITOR="${_editor}" tmux_oneshot --edit 2>/dev/null)"
rm -rf "${_xdg_c}" "${_xdg_d}" "${_xdg_s}" "${_extra1}" "${_fake_home}"

# ---------------------------------------------------------------------------
# Picker: _resolve_pick (pure), the --expect key list, and _pick through the
# stub. Uses the AWS/keys DB: ap=0 aP=1 apa=2 aps=3 app=4 aPa=5 aPs=6
# "ap login"=7 caffeinate=8 go=9 claude-link=10.
# ---------------------------------------------------------------------------
export TMUX_ONESHOT_DB="${_db2}"
local _row_aPs _row_ap _row_apa
_row_aPs="$(tmux_oneshot::_menu | sed -n 7p)"
_row_ap="$(tmux_oneshot::_menu | sed -n 1p)"
_row_apa="$(tmux_oneshot::_menu | sed -n 3p)"
_t "key beats query and selection" "8" "$(tmux_oneshot::_resolve_pick 0 "aps" "ctrl-k" "${_row_aPs}")"
_t "key with rc 1 (zero matches) still resolves" "8" "$(tmux_oneshot::_resolve_pick 1 "zzz" "ctrl-k" "")"
_err_out="$(tmux_oneshot::_resolve_pick 0 "" "ctrl-x" "" 2>&1)"; _err_rc=$?
_t "unbound key: rc 1" "1" "${_err_rc}"
_t "unbound key: names it" "Unbound direct key | key='ctrl-x'" "$(print -r -- "${_err_out}" | grep -o "Unbound direct key.*")"
_t "exact query beats fuzzy selection" "3" "$(tmux_oneshot::_resolve_pick 0 "aps" "" "${_row_aPs}")"
_t "exact query is case-sensitive" "1" "$(tmux_oneshot::_resolve_pick 0 "aP" "" "${_row_ap}")"
_t "fuzzy: selection wins when query is not a name" "2" "$(tmux_oneshot::_resolve_pick 0 "alp" "" "${_row_apa}")"
_err_out="$(tmux_oneshot::_resolve_pick 130 "ap" "" "" 2>&1)"; _err_rc=$?
_t "rc 130 aborts" "1 Aborted" "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'Aborted')"
_err_out="$(tmux_oneshot::_resolve_pick 0 "" "" "" 2>&1)"; _err_rc=$?
_t "nothing → rc 1, No entry selected" "1 No entry selected" "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'No entry selected')"

# Group prefixes: the bare leaf resolves when unique, never when two groups share it.
local _db3 _saved_db
_db3="$(mktemp /tmp/tmux-oneshot-test-db3.XXXXX.json)"
cat > "${_db3}" << 'EOF'
[
 {"menu": {"name": "applepaste", "text": "type the clipboard"}, "cmd": "echo paste"},
 {"menu": {"name": "aws/ap", "text": "pick env"}, "cmd": "echo ap"},
 {"menu": {"name": "aws/app", "text": "production"}, "cmd": "echo app"},
 {"menu": {"name": "aws/aPp", "text": "all production"}, "cmd": "echo aPp"},
 {"menu": {"name": "aws/foo", "text": "a"}, "cmd": "echo a"},
 {"menu": {"name": "gcp/foo", "text": "b"}, "cmd": "echo b"}
]
EOF
_saved_db="${TMUX_ONESHOT_DB}"
export TMUX_ONESHOT_DB="${_db3}"
_t "leaf resolves through its group prefix" "2" "$(tmux_oneshot::_index_or_die app)"
_t "leaf match is whole-segment, not a prefix of another name" "1" "$(tmux_oneshot::_index_or_die ap)"
_t "full grouped name still resolves" "2" "$(tmux_oneshot::_index_or_die aws/app)"
_t "leaf stays case-sensitive" "3" "$(tmux_oneshot::_index_or_die aPp)"
_err_out="$(tmux_oneshot::_index_or_die foo 2>&1)"; _err_rc=$?
_t "leaf shared by two groups is unknown" "1 Unknown key" "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'Unknown key')"
_t "picker: typed leaf beats the highlighted row" "2" "$(tmux_oneshot::_resolve_pick 0 "app" "" "$(tmux_oneshot::_menu | sed -n 1p)")"
export TMUX_ONESHOT_DB="${_saved_db}"
rm -f "${_db3}"

_t "expect list = unique non-reserved keys" "ctrl-g,ctrl-k,ctrl-l" "$(tmux_oneshot::_expect_keys 2>/dev/null)"
_t "debug key list" "ctrl-k→caffeinate   ctrl-g→go   ctrl-l→claude-link" "$(tmux_oneshot::_key_list)"
# fzf lists bottom-up: keyed rows are emitted last so they sit at the top of the popup.
_t "keyed rows come last and start with their key label" "8 ⌃k|9 ⌃g|10 ⌃l" \
  "$(tmux_oneshot::_menu | tail -3 | while IFS=$'\t' read -r _idx _rest; do print -r -- "${_idx} ${_rest%% *}"; done | paste -sd'|' -)"
_t "unkeyed rows keep the key column blank" "   ap" "$(tmux_oneshot::_menu | sed -n 1p | cut -f2 | cut -c1-5)"
# The default styles must be real escape bytes, not the literal text $'\e[…'.
_t "default key style is a real ESC sequence" "$(print -rn -- $'\e[1;35m' | od -An -c | tr -s ' ')" \
  "$(zsh -c 'source "$1"; print -rn -- "${TMUX_ONESHOT_KEY_STYLE}" | od -An -c | tr -s " "' _ "${HOME}/.config/bin/tmux-oneshot" 2>/dev/null)"
_t "styled key column carries the escape and the reset" "yes" \
  "$(TMUX_ONESHOT_KEY_STYLE=$'\e[1m' tmux_oneshot::_menu | tail -3 | head -1 | cut -f2 | { IFS= read -r l; [[ "${l}" == $'\e[1m'*$'\e[0m'* ]] && echo yes; })"
_t "unkeyed rows come first and hold no key label" "0" "$(tmux_oneshot::_menu | head -8 | grep -c '⌃')"
local _db_keys
_db_keys="$(mktemp /tmp/tmux-oneshot-test-dbkeys.XXXXX.json)"
echo '[{"cmd": "a", "key": "ctrl-u"}, {"cmd": "b", "key": "enter"}, {"cmd": "c", "key": "ctrl-k"}]' > "${_db_keys}"
_err_out="$(TMUX_ONESHOT_DB="${_db_keys}" tmux_oneshot::_expect_keys 2>&1 >/dev/null)"; _err_rc=$?
_t "reserved keys dropped: survivors listed" "ctrl-k" "$(TMUX_ONESHOT_DB="${_db_keys}" tmux_oneshot::_expect_keys 2>/dev/null)"
_t "reserved keys dropped: rc 1, one error each" "1 2" "${_err_rc} $(print -r -- "${_err_out}" | grep -c 'Reserved direct key ignored')"
echo '[{"cmd": "a", "key": "C-k"}]' > "${_db_keys}"
_err_out="$(TMUX_ONESHOT_DB="${_db_keys}" tmux_oneshot::_expect_keys 2>&1 >/dev/null)"; _err_rc=$?
_t "unsupported key name: direct keys disabled" "1 Direct keys disabled: unsupported key: C-k" \
  "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'Direct keys disabled.*')"
_t "unsupported key name: expect list empty" "" "$(TMUX_ONESHOT_DB="${_db_keys}" tmux_oneshot::_expect_keys 2>/dev/null)"
TMUX_ONESHOT_DB="${_db_keys}" tmux_oneshot::action::debug > /dev/null 2>&1
_t "unsupported key name: --debug rc 1" "1" "$?"
rm -f "${_db_keys}"

: > "${_tmux_file}"
_set_picks $'\tctrl-k\t'
( export TMUX=test-dummy; tmux_oneshot::_pick > /dev/null 2>&1 )
_t "_pick e2e: direct key with zero matches runs caffeinate in window caf" "new-window|-n|caf" \
  "$(_tmux_last 1-3)"
_t "_pick passes --expect and no header to fzf" "--expect=ctrl-g,ctrl-k,ctrl-l 0" \
  "$(tail -1 "${_calls_file}" | grep -o -- '--expect=[^ ]*') $(tail -1 "${_calls_file}" | grep -c -- '--header=')"
_t "_pick preview is the shared program on the hidden index" "--preview jq -r --arg i {1} ${(qq)TMUX_ONESHOT_JQ_PREVIEW} ${(qq)_db2}" \
  "$(tail -1 "${_calls_file}" | grep -o -- '--preview .*' | sed 's/ --preview-window.*//')"
_set_picks $'apa\t\taPa'
_t "_pick e2e: exact name beats the highlighted row" "aws_profile --query 'alpha' 'hyperbase' " \
  "$(tmux_oneshot::_pick 2>/dev/null)"
_set_picks $'\t\t'"${_row_apa%%$'\t'*}"$'\t'
_t "_pick e2e: highlighted row runs" "aws_profile --query 'alpha' 'hyperbase' " \
  "$(tmux_oneshot::_pick 2>/dev/null)"
_set_picks "ESC"
_err_out="$(tmux_oneshot::_pick 2>&1)"; _err_rc=$?
_t "_pick e2e: esc aborts" "1 Aborted" "${_err_rc} $(print -r -- "${_err_out}" | grep -o Aborted)"

# A command that exits FZF_GROUP_BACK_RC (esc inside its own picker) is "back", not a failure.
local _db_back _out_back
_db_back="$(mktemp /tmp/tmux-oneshot-test-dbback.XXXXX.json)"
_out_back="$(mktemp /tmp/tmux-oneshot-test-outback.XXXXX)"
cat > "${_db_back}" << 'EOF'
[
 {"menu": {"name": "inner", "text": "has its own picker"}, "cmd": "(exit 130)", "autodismiss": true},
 {"menu": {"name": "plain", "text": "plain"}, "cmd": "echo plain-ran", "autodismiss": true}
]
EOF
_saved_db="${TMUX_ONESHOT_DB}"
export TMUX_ONESHOT_DB="${_db_back}"
_set_picks $'inner\t\t' $'plain\t\t'
: > "${_calls_file}"
_err_out="$(tmux_oneshot::_pick 2>&1 > "${_out_back}")"; _err_rc=$?
_t "_pick e2e: a command exiting 130 reopens the top-level picker, which runs the next pick" "0 plain-ran 2 Cancelled" \
  "${_err_rc} $(cat "${_out_back}") $(wc -l < "${_calls_file}" | tr -d ' ') $(print -r -- "${_err_out}" | grep -o Cancelled)"
_t "_pick e2e: the 130 exit is not marked as a failure" "0" "$(print -r -- "${_err_out}" | grep -c 'failed')"
export TMUX_ONESHOT_DB="${_saved_db}"
rm -f "${_db_back}" "${_out_back}"

# Groups: "g/leaf" names fold into one top-level row that opens a second picker.
local _db4
_db4="$(mktemp /tmp/tmux-oneshot-test-db4.XXXXX.json)"
cat > "${_db4}" << 'EOF'
[
 {"menu": {"name": "misc", "text": "ungrouped"}, "cmd": "echo misc-ran", "autodismiss": true},
 {"menu": {"name": "aws/apa", "text": "alpha"}, "cmd": "echo apa-ran", "autodismiss": true},
 {"menu": {"name": "aws/aps", "text": "staging"}, "cmd": "echo aps-ran", "autodismiss": true}
]
EOF
_saved_db="${TMUX_ONESHOT_DB}"
export TMUX_ONESHOT_DB="${_db4}"
_t "top menu folds the group into one row" "0|g:aws" "$(tmux_oneshot::_menu | cut -f1 | paste -sd'|' -)"
_t "group row lists its leaves" "aws   ▸ apa, aps" "$(tmux_oneshot::_menu | sed -n 2p | cut -f2)"
_t "group menu shows leaves with real indexes" "1|apa|2|aps" "$(tmux_oneshot::_menu --group aws | cut -f1-2 | sed 's/  .*//' | tr '\t' '|' | paste -sd'|' -)"
_t "highlighted group row resolves to g:aws" "g:aws" "$(tmux_oneshot::_resolve_pick 0 "" "" "$(tmux_oneshot::_menu | sed -n 2p)")"
_t "--list prints every name" "misc aws/apa aws/aps" "$(tmux_oneshot --list | paste -sd' ' -)"
_t "--list --depth 1 collapses groups to one name" "misc aws" "$(tmux_oneshot --list --depth 1 | paste -sd' ' -)"
_t "--list --prefix keeps matching names" "aws/apa aws/aps" "$(tmux_oneshot --list --prefix aws | paste -sd' ' -)"
_t "--list --list-depth and --prefix compose" "aws" "$(tmux_oneshot --list --list-depth 1 --prefix a | paste -sd' ' -)"
_t "--list rejects a non-numeric depth" "1" "$(tmux_oneshot --list --depth x 2>/dev/null; print -rn -- $?)"
_set_picks $'\t\t▸' $'\t\taps'
_t "_pick e2e: group row opens the group picker and runs the leaf" "aps-ran" "$(tmux_oneshot::_pick 2>/dev/null)"
_set_picks $'apa\t\t'
_t "_pick e2e: typed leaf runs at once from the top level" "apa-ran" "$(tmux_oneshot::_pick 2>/dev/null)"
_set_picks $'\t\t▸' "ESC" "ESC"
: > "${_calls_file}"
_err_out="$(tmux_oneshot::_pick 2>&1)"; _err_rc=$?
_t "esc in the group picker goes back to the top level; esc again aborts" "1 Aborted 3" \
  "${_err_rc} $(print -r -- "${_err_out}" | grep -o Aborted) $(wc -l < "${_calls_file}" | tr -d ' ')"
_t "the group picker is an fzf_group named aws (header, prompt, alt-enter verbatim)" "yes" \
  "$([[ "$(sed -n 2p "${_calls_file}")" == *"--prompt=aws/  --header=aws/   esc: back   alt-enter: typed name verbatim --print-query --bind=alt-enter:print-query"* ]] && echo yes)"
_set_picks $'\t\t▸' $'apa\t\t'
_t "_pick e2e: alt-enter in the group picker runs the typed leaf, no row picked" "apa-ran" "$(tmux_oneshot::_pick 2>/dev/null)"
_t "--dry-run of a group lists its members" "group=aws members=apa, aps" "$(tmux_oneshot::action::dry_run aws)"
_t "--debug is clean with a folded group" "0" "$(tmux_oneshot::action::debug > /dev/null 2>&1; echo $?)"
_t "preview for a group row: group · colored name, then its leaves" $'group · \e[36maws/\e[0m\napa   aps' \
  "$(jq -r --arg i g:aws "${TMUX_ONESHOT_JQ_PREVIEW}" "${_db4}")"
export TMUX_ONESHOT_DB="${_saved_db}"
rm -f "${_db4}"
export TMUX_ONESHOT_DB="${_db}"
_set_picks $'\t\tMy Name'
_t "keyless DB: 2-line --print-query output parses" "named-ran" "$(tmux_oneshot::_pick 2>/dev/null)"
_t "keyless DB: no --expect passed" "" "$(tail -1 "${_calls_file}" | grep -o -- '--expect=')"
export TMUX_ONESHOT_DB="${_db2}"

# Real fzf: the exact-prefix name must outrank a shorter line. Fails on the
# default tiebreak (length) and on any --nth 2.
_t "ranking regression (real fzf): 'ap' beats 'apa' despite the longer text" "0" \
  "$(fzf --filter=ap "${TMUX_ONESHOT_FZF_MATCH_ARGS[@]}" <<< "$(tmux_oneshot::_menu)" | head -1 | cut -f1)"

# ---------------------------------------------------------------------------
# Run modes: flat entries never open the builder; window; prompt; flash
# ---------------------------------------------------------------------------
local _calls_before
_calls_before="$(wc -l < "${_calls_file}")"
_t "immediate entry runs its cmd" "aws_profile --query 'alpha' 'hyperbase' " "$(_run_key apa 2>/dev/null)"
_t "immediate entry never calls _fzf" "${_calls_before}" "$(wc -l < "${_calls_file}")"
: > "${_tmux_file}"
( export TMUX=test-dummy; _run_key aPa > /dev/null 2>&1 )
_t "autodismiss flashes '✓ <name>'" "display-message|-d|1500|✓ aPa" "$(_tmux_last)"

: > "${_tmux_file}"
_err_out="$(export TMUX=test-dummy; _run_key 'ap login' 2>/dev/null)"; _err_rc=$?
_t "window entry: rc 0, no hold" "0 " "${_err_rc} $(print -r -- "${_err_out}" | grep HELD)"
_t "window entry: opens its named window" "new-window|-n|sso" "$(_tmux_last 1-3)"
_t "window entry: cmd travels as one argv element, then the window name" "ACTION=login ${_stub} --query \"'hyperbase' \"|sso" "$(_tmux_last 10-)"
: > "${_tmux_file}"
( export TMUX=test-dummy; _run_key caffeinate > /dev/null 2>&1 )
_t "_new_window argv: -n name -c pwd zsh -c runner tmux-oneshot cmd name" \
  "new-window|-n|caf|-c|${PWD}|zsh|-c|${TMUX_ONESHOT_WINDOW_RUNNER}|tmux-oneshot|echo caf-ran|caf" "$(_tmux_last)"
: > "${_tmux_file}"
( export TMUX=test-dummy ONESHOT_INPUT="foo bar"; tmux_oneshot::_new_window sso 'echo x' > /dev/null 2>&1 )
_t "_new_window forwards ONESHOT_INPUT with -e" "-e|ONESHOT_INPUT=foo bar" "$(_tmux_last 6-7)"
_err_out="$(unset TMUX; tmux_oneshot::_new_window caf 'echo inline-ran' 2>&1)"
_t "_new_window outside tmux runs inline" "inline-ran" "$(print -r -- "${_err_out}" | grep -x inline-ran)"
_t "_new_window outside tmux warns" "Not inside tmux" "$(print -r -- "${_err_out}" | grep -o 'Not inside tmux')"

# ---------------------------------------------------------------------------
# Surface: entry.window wins; else TMUX_ONESHOT_SURFACE; popup_pane attaches a throwaway session
# ---------------------------------------------------------------------------
# First recorded tmux argv starting with <cmd>, fields <range> (cut syntax), |-joined.
function _tmux_call() { grep -m1 -e "^${1}"$'\x1f' "${_tmux_file}" | cut -d $'\x1f' -f "${2:-1-}" | tr $'\x1f' '|' }
# The recorded tmux subcommands in order; a leading "-S <socket>" is stripped first.
function _tmux_subcommands() { sed -E $'s/^-S\x1f[^\x1f]*\x1f//' "${_tmux_file}" | cut -d $'\x1f' -f1 | grep -E "${1}" | paste -sd'|' - }
_t "surface: default is popup_pane" "popup_pane" "$(unset TMUX_ONESHOT_SURFACE; tmux_oneshot::_surface '{"cmd":"x"}')"
_t "surface: TMUX_ONESHOT_SURFACE=popup opts out" "popup" "$(TMUX_ONESHOT_SURFACE=popup tmux_oneshot::_surface '{"cmd":"x"}')"
_t "surface: TMUX_ONESHOT_SURFACE picks popup_pane" "popup_pane" "$(TMUX_ONESHOT_SURFACE=popup_pane tmux_oneshot::_surface '{"cmd":"x"}')"
_t "surface: an entry's window field wins" "window" "$(TMUX_ONESHOT_SURFACE=popup_pane tmux_oneshot::_surface '{"cmd":"x","window":"w"}')"
_err_out="$(TMUX_ONESHOT_SURFACE=bogus tmux_oneshot::_surface '{"cmd":"x"}' 2>&1)"
_t "surface: unknown value falls back to the default and says so" "popup_pane Unknown surface" \
  "$(print -r -- "${_err_out}" | tail -1) $(print -r -- "${_err_out}" | grep -o 'Unknown surface')"
: > "${_tmux_file}"
( export TMUX=test-dummy TMUX_ONESHOT_SURFACE=window; _run_key aPa > /dev/null 2>&1 )
_t "surface=window: a plain entry opens a window named after it" "new-window|-n|aPa" "$(_tmux_last 1-3)"
: > "${_tmux_file}"
_err_out="$(export TMUX=test-dummy TMUX_ONESHOT_SURFACE=popup_pane; _run_key aPa 2>/dev/null)"; _err_rc=$?
_t "surface=popup_pane: new-session -d -s oneshot-<pid> -c pwd zsh -c pane-runner" \
  "new-session|-d|-s|oneshot-$$|-c|${PWD}|zsh|-c|${TMUX_ONESHOT_PANE_RUNNER}|tmux-oneshot" "$(_tmux_call new-session 1-10)"
_t "surface=popup_pane: cmd, autodismiss and the back rc follow the runner" \
  "${_stub} --query \"'alpha' \"|true|${FZF_GROUP_BACK_RC}" "$(_tmux_call new-session 11)|$(_tmux_call new-session 13-14)"
_t "surface=popup_pane: attaches to that session, naming this server's socket" "-S|test-dummy|attach-session|-t|oneshot-$$" "$(_tmux_call -S)"
_t "surface=popup_pane: status off, attach, then kill the session" "set-option|attach-session|kill-session" \
  "$(_tmux_subcommands '^(set-option|attach-session|kill-session)$')"
_t "surface=popup_pane: no rc back (popup closed mid-run) is a failure, and the popup never holds" "1 " \
  "${_err_rc} $(print -r -- "${_err_out}" | grep HELD)"
_err_out="$(unset TMUX; TMUX_ONESHOT_SURFACE=popup_pane tmux_oneshot::_attach_session aPa 'echo inline-ran' true 2>&1)"
_t "surface=popup_pane outside tmux runs inline" "inline-ran" "$(print -r -- "${_err_out}" | grep -x inline-ran)"
# The runner itself, headless: TMUX_ONESHOT_HOLD=0 (exported above) skips its esc read.
local _rcf
_rcf="$(mktemp /tmp/tmux-oneshot-test-rc.XXXXX)"
_err_out="$(zsh -c "${TMUX_ONESHOT_PANE_RUNNER}" tmux-oneshot 'echo ran; (exit 3)' "${_rcf}" false "${FZF_GROUP_BACK_RC}" 2>&1)"; _err_rc=$?
_t "pane runner: rc reaches the file and the exit; a failure shows its rc and holds" "3 3 ran rc=3 esc" \
  "${_err_rc} $(cat "${_rcf}") $(print -r -- "${_err_out}" | grep -x ran) $(print -r -- "${_err_out}" | grep -o 'rc=3') $(print -r -- "${_err_out}" | grep -o 'esc')"
_err_out="$(zsh -c "${TMUX_ONESHOT_PANE_RUNNER}" tmux-oneshot 'echo ok' "${_rcf}" true "${FZF_GROUP_BACK_RC}" 2>&1)"; _err_rc=$?
_t "pane runner: an autodismissed success exits without holding" "0 0 ok " \
  "${_err_rc} $(cat "${_rcf}") $(print -r -- "${_err_out}" | grep -x ok) $(print -r -- "${_err_out}" | grep -o 'esc')"
_err_out="$(zsh -c "${TMUX_ONESHOT_PANE_RUNNER}" tmux-oneshot 'echo ok' "${_rcf}" false "${FZF_GROUP_BACK_RC}" 2>&1)"; _err_rc=$?
_t "pane runner: a held success shows only the esc banner" "0 esc " \
  "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'esc') $(print -r -- "${_err_out}" | grep -o 'rc=')"
_err_out="$(zsh -c "${TMUX_ONESHOT_PANE_RUNNER}" tmux-oneshot "(exit ${FZF_GROUP_BACK_RC})" "${_rcf}" false "${FZF_GROUP_BACK_RC}" 2>&1)"; _err_rc=$?
_t "pane runner: a cancel skips the hold" "${FZF_GROUP_BACK_RC} " "${_err_rc} $(print -r -- "${_err_out}" | grep -o 'esc')"
rm -f "${_rcf}"

_set_typed "foo bar"
_t "prompt entry exports ONESHOT_INPUT into cmd" "https://go/foo bar" "$(_run_key go 2>/dev/null)"
_t "prompt label is shown verbatim" "go/ " "$(cat "${_label_file}")"
_t "prompt value dies with the run" "" "${ONESHOT_INPUT-}"
_set_typed ""
_err_out="$(_run_key go 2>&1)"; _err_rc=$?
_t "empty prompt aborts: rc 1" "1" "${_err_rc}"
_t "empty prompt aborts: says so, nothing evaluated" "Aborted: empty input" \
  "$(print -r -- "${_err_out}" | grep -o 'Aborted: empty input'; print -r -- "${_err_out}" | grep 'https://go/')"

# ---------------------------------------------------------------------------
# AWS sequences (inline fixture, stub script): the shipped aws_profile.json
# entries assemble to exactly the alias bodies, with no builder.
# ---------------------------------------------------------------------------
_t "--dry-run app: surface fields" "name=app tier=db src=${_db2} surface=popup autodismiss=true key=- prompt=-" \
  "$(tmux_oneshot --dry-run app 2>/dev/null | sed -n 1p)"
_t "--dry-run app: cmd" "cmd=${_stub} --query \"'production' 'hyperbase' \"" \
  "$(tmux_oneshot --dry-run app 2>/dev/null | sed -n 2p)"
_t "--dry-run 'ap login': surface window:sso" "surface=window:sso autodismiss=false" \
  "$(tmux_oneshot --dry-run 'ap login' 2>/dev/null | grep -o 'surface=[^ ]* autodismiss=[^ ]*')"
_t "--dry-run 'ap login': cmd" "cmd=ACTION=login ${_stub} --query \"'hyperbase' \"" \
  "$(tmux_oneshot --dry-run 'ap login' 2>/dev/null | sed -n 2p)"
_t "--dry-run go: prompt left unexpanded" "cmd=echo \"https://go/\${ONESHOT_INPUT}\"" \
  "$(tmux_oneshot --dry-run go 2>/dev/null | sed -n 2p)"
_t "--dry-run caffeinate: key and window" "surface=window:caf autodismiss=false key=ctrl-k" \
  "$(tmux_oneshot --dry-run caffeinate 2>/dev/null | grep -o 'surface=.*key=[^ ]*')"
_t "--dry-run unknown: rc 1" "1" "$(tmux_oneshot --dry-run nope >/dev/null 2>&1; echo $?)"
_t "apa and aPa resolve to different entries" "2 5" \
  "$(tmux_oneshot::_index_or_die apa) $(tmux_oneshot::_index_or_die aPa)"
export TMUX_ONESHOT_DB="${_db}"

# ---------------------------------------------------------------------------
# Error capture: executed runs persist stderr to TMUX_ONESHOT_LOG (rotated
# per run), so popup errors survive the popup closing. TMUX= keeps the
# executed runs (separate processes, no tmux stub) off the live server.
# ---------------------------------------------------------------------------
local _log_dir _log
_log_dir="$(mktemp -d /tmp/tmux-oneshot-test-log.XXXXX)"
_log="${_log_dir}/log.txt"
export TMUX_ONESHOT_LOG="${_log}"

# Regression for the popup outage of 2026-08-19: a spaced key must survive
# the executed CLI path end to end.
_t "CLI select by spaced name" "named-ran" \
  "$(TMUX= zsh "${HOME}/.config/bin/tmux-oneshot" "My Name" 2>/dev/null | grep -o named-ran)"
_t "CLI: apa runs the stub with the alias body" "aws_profile --query 'alpha' 'hyperbase' " \
  "$(TMUX_ONESHOT_DB="${_db2}" TMUX= zsh "${HOME}/.config/bin/tmux-oneshot" apa 2>/dev/null)"

zsh "${HOME}/.config/bin/tmux-oneshot" --list > /dev/null 2>&1
_t "run logs its invocation header" "1" "$(grep -c 'tmux-oneshot --list' "${_log}")"
_t "run logs its exit code" "── exit rc=0" "$(grep '── exit' "${_log}")"

zsh "${HOME}/.config/bin/tmux-oneshot" bogus-key > /dev/null 2>&1
_t "failed run: rc 1 logged" "── exit rc=1" "$(grep '── exit' "${_log}")"
_t "failed run: stderr captured in log" "1" "$(grep -c 'Unknown key' "${_log}")"
_t "log has no ANSI escapes (the tty copy keeps them)" "0" "$(grep -c $'\e' "${_log}")"
_t "log still carries the level tag" "1" "$(grep -c '^\[ERROR\]' "${_log}")"
_t "previous run rotated aside" "1" "$(grep -c 'tmux-oneshot --list' "${_log}.bak.1")"

_t "--log prints path and content without rotating" "1" \
  "$(zsh "${HOME}/.config/bin/tmux-oneshot" --log | grep -c 'Unknown key')"
_t "--log did not rotate" "── exit rc=1" "$(grep '── exit' "${_log}")"

# Failures notify; the click opens the log in a tmux window. Cancels stay silent.
local _ndir
_ndir="$(mktemp -d /tmp/tmux-oneshot-test-notif.XXXXX)"
print -rl -- '#!/usr/bin/env zsh' "print -r -- \"\$*\" >> '${_ndir}/calls'" > "${_ndir}/terminal-notifier"
chmod +x "${_ndir}/terminal-notifier"
: > "${_ndir}/calls"
# Entry 4 of the first DB is `false`.
TMUX_ONESHOT_NOTIFY=1 TMUX=/tmp/fake-sock,1,0 PATH="${_ndir}:${PATH}" TMUX_ONESHOT_DB="${_db}" \
  zsh "${HOME}/.config/bin/tmux-oneshot" 4 > /dev/null 2>&1
_t "a failed entry names itself, cmd and rc in the log" "1" "$(grep -c "false failed | rc='1' cmd='false'" "${_log}")"
_t "a failed run copies its log to last-error.log" "yes" "$(grep -q "false failed | rc='1'" "${_log:h}/last-error.log" && echo yes)"
_t "a failed run notifies; the click opens the log in a new tmux window on this server" "yes" \
  "$(grep -q -E -- "-execute /[^ ]+/tmux -S /tmp/fake-sock new-window -n oneshot-error /[^ ]+ \+ ${_log:h}/last-error.log" "${_ndir}/calls" && echo yes)"
_t "the notification carries the failure line" "1" "$(grep -c -- "-message false failed | rc='1'" "${_ndir}/calls")"
_t "the failure marker is consumed" "no" "$([[ -f "${_log}.failed" ]] && echo yes || echo no)"
: > "${_ndir}/calls"
TMUX_ONESHOT_NOTIFY=0 PATH="${_ndir}:${PATH}" TMUX_ONESHOT_DB="${_db}" zsh "${HOME}/.config/bin/tmux-oneshot" 4 > /dev/null 2>&1
_t "TMUX_ONESHOT_NOTIFY=0 posts nothing" "0" "$(wc -l < "${_ndir}/calls" | tr -d ' ')"
TMUX_ONESHOT_NOTIFY=1 PATH="${_ndir}:${PATH}" TMUX_ONESHOT_DB="${_db}" zsh "${HOME}/.config/bin/tmux-oneshot" 3 > /dev/null 2>&1
_t "a successful run posts nothing" "0" "$(wc -l < "${_ndir}/calls" | tr -d ' ')"
export TMUX_ONESHOT_LOG="${_log}"
tmux_oneshot::_resolve_pick 130 "" "" "" > /dev/null 2>&1
_t "esc is a cancel, never a failure" "no" "$([[ -f "${_log}.failed" ]] && echo yes || echo no)"
rm -rf "${_ndir}"

unset TMUX_ONESHOT_LOG
rm -rf "${_log_dir}"

# ---------------------------------------------------------------------------
# Group header: a "<group>/" entry lends its key and text to the group row and
# has no row of its own; its key opens the group.
# ---------------------------------------------------------------------------
local _db5; _db5="$(mktemp /tmp/tmux-oneshot-test-db5.XXXXX.json)"
cat > "${_db5}" << 'EOF'
[
  {"menu": {"name": "vi_/", "text": "edit a common file"}, "key": "ctrl-v"},
  {"menu": {"name": "vi_/cset", "text": "claude_settings_local"}, "cmd": "echo cset", "window": "vi_"},
  {"menu": {"name": "vi_/kh", "text": "karabiner_home"}, "cmd": "echo kh", "window": "vi_"},
  {"menu": {"name": "plain"}, "cmd": "echo plain"}
]
EOF
export TMUX_ONESHOT_DB="${_db5}"
_t "header: one plain row, then the group row keyed and described by its header" \
  $'3\t   plain  echo plain\ng:vi_\t⌃v vi_    ▸ edit a common file · cset, kh' "$(tmux_oneshot::_menu)"
_t "header: the group view lists only real leaves" "1 2" "$(tmux_oneshot::_menu --group vi_ | cut -f1 | paste -sd' ' -)"
_t "header: its key resolves to the group" "g:vi_" "$(tmux_oneshot::_resolve_pick 0 "" "ctrl-v" "")"
_t "header: ctrl-v is a usable direct key" "ctrl-v" "$(tmux_oneshot::_expect_keys 2>/dev/null)"
_t "header: preview lists the leaves without an empty one" "cset   kh" "$(jq -r --arg i g:vi_ "${TMUX_ONESHOT_JQ_PREVIEW}" "${_db5}" | sed -n 2p)"
( tmux_oneshot --debug > /dev/null 2>&1 )
_t "header: --debug clean" "0" "$?"
echo '[{"menu": {"name": "lonely/"}, "key": "ctrl-x"}, {"cmd": "echo x"}]' > "${_db5}"
_err_out="$(tmux_oneshot --debug 2>&1 >/dev/null)"; _err_rc=$?
_t "header without members: --debug fails and names it" "1 Group header without members | header='lonely/'" \
  "${_err_rc} $(print -r -- "${_err_out}" | grep -o "Group header without members | header='[^']*'")"
rm -f "${_db5}"
export TMUX_ONESHOT_DB="${_db}"

# ---------------------------------------------------------------------------
rm -f "${_picks_file}" "${_typed_file}" "${_calls_file}" "${_label_file}" "${_tmux_file}" "${_db}" "${_db2}"
rm -rf "${_stub_dir}"
unfunction tmux _tmux_last _fresh 2>/dev/null
print
if (( _fail > 0 )); then
  log::err "tmux_oneshot: ${_pass} passed, ${_fail} failed"
  return 1
fi
log::info "tmux_oneshot: all ${_pass} passed"
