# Tests for tmux.zsh — tcap / tmux::_slice_history
# Only runs when OTTO_TEST__ZSH_PLUGINS_TMUX=true
[[ "$OTTO_TEST__ZSH_PLUGINS_TMUX" == "true" ]] || return 0

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
local _pass=0 _fail=0 _skip=0
local _test_include="${OTTO_TEST__ZSH_PLUGINS_TMUX_INCLUDE:-}"
local _test_exclude="${OTTO_TEST__ZSH_PLUGINS_TMUX_EXCLUDE:-}"
local _test_list="${OTTO_TEST__ZSH_PLUGINS_TMUX_LIST:-false}"

# Source log functions
source "${0:h}/log.zsh"

function _t_should_run() {
  local name="$1"
  if [[ -n "$_test_include" ]] && [[ "$name" != ${~_test_include} ]]; then
    return 1
  fi
  if [[ -n "$_test_exclude" ]] && [[ "$name" == ${~_test_exclude} ]]; then
    return 1
  fi
  return 0
}

function _t() {
  local name="$1" expected="$2" actual="$3"
  if ! _t_should_run "$name"; then
    ((_skip++))
    return
  fi
  if [[ "$_test_list" == "true" ]]; then
    print -r -- "$name"
    return
  fi
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

function _t_rc() {
  local name="$1" expected_rc="$2"
  shift 2
  if ! _t_should_run "$name"; then
    ((_skip++))
    return
  fi
  if [[ "$_test_list" == "true" ]]; then
    print -r -- "$name"
    return
  fi
  "$@" >/dev/null 2>&1
  _t "$name" "$expected_rc" "$?"
}

# Helper: build mock scrollback (already tac'd — most recent at top)
# Each command block in the reversed stream is: output line(s), prompt line, [extra prompt lines]
function _mock() { print -r -- "$1" | tmux::_slice_history "$2" "$3" "$4" }

# ---------------------------------------------------------------------------
# Mock data: 4 commands, 1-line prompt, already reversed (as if after tac)
#
# In the reversed stream, output appears BEFORE its prompt line:
#   "four"           ← output of cmd4
#   "❯ echo four"    ← prompt+command for cmd4 (most recent, index 1)
#   "three"          ← output of cmd3
#   "❯ echo three"   ← prompt+command for cmd3 (index 2)
#   ...
# ---------------------------------------------------------------------------
_REV="four
❯ echo four
three
❯ echo three
two
❯ echo two
one
❯ echo one"

# Override prompt line count to 1 (no extra lines)
function tmux::_prompt_line_count() { echo 1 }

# ---------------------------------------------------------------------------
# _slice_history — single command extraction
# ---------------------------------------------------------------------------
_t "slice 1..1 (most recent)" \
  "$(printf 'four\n❯ echo four')" \
  "$(_mock "$_REV" 1 1 '❯')"

_t "slice 2..2 (2nd most recent)" \
  "$(printf 'three\n❯ echo three')" \
  "$(_mock "$_REV" 2 2 '❯')"

_t "slice 3..3" \
  "$(printf 'two\n❯ echo two')" \
  "$(_mock "$_REV" 3 3 '❯')"

_t "slice 4..4 (oldest)" \
  "$(printf 'one\n❯ echo one')" \
  "$(_mock "$_REV" 4 4 '❯')"

# ---------------------------------------------------------------------------
# _slice_history — ranges
# ---------------------------------------------------------------------------
_t "slice 1..2 (two most recent)" \
  "$(printf 'four\n❯ echo four\nthree\n❯ echo three')" \
  "$(_mock "$_REV" 1 2 '❯')"

_t "slice 2..3 (middle two)" \
  "$(printf 'three\n❯ echo three\ntwo\n❯ echo two')" \
  "$(_mock "$_REV" 2 3 '❯')"

_t "slice 1..4 (all commands)" \
  "$(printf 'four\n❯ echo four\nthree\n❯ echo three\ntwo\n❯ echo two\none\n❯ echo one')" \
  "$(_mock "$_REV" 1 4 '❯')"

_t "slice 3..4 (two oldest)" \
  "$(printf 'two\n❯ echo two\none\n❯ echo one')" \
  "$(_mock "$_REV" 3 4 '❯')"

# ---------------------------------------------------------------------------
# _slice_history — out of range
# ---------------------------------------------------------------------------
_t_rc "slice 5..5 (out of range → rc=1)" 1 \
  _mock "$_REV" 5 5 '❯'

_t_rc "slice 10..10 (way out of range → rc=1)" 1 \
  _mock "$_REV" 10 10 '❯'

# ---------------------------------------------------------------------------
# _slice_history — multi-line output per command
# ---------------------------------------------------------------------------
_REV_MULTIOUT="line2 of four
line1 of four
❯ echo four
line2 of three
line1 of three
❯ echo three"

_t "multi-line output, slice 1..1" \
  "$(printf 'line2 of four\nline1 of four\n❯ echo four')" \
  "$(_mock "$_REV_MULTIOUT" 1 1 '❯')"

_t "multi-line output, slice 1..2" \
  "$(printf 'line2 of four\nline1 of four\n❯ echo four\nline2 of three\nline1 of three\n❯ echo three')" \
  "$(_mock "$_REV_MULTIOUT" 1 2 '❯')"

# ---------------------------------------------------------------------------
# _slice_history — 2-line prompt (extra_lines=1)
# In reversed stream, extra prompt line appears AFTER the prompt match line
# ---------------------------------------------------------------------------
function tmux::_prompt_line_count() { echo 2 }

_REV_2LINE="two
❯ echo two
~/projects
one
❯ echo one
~/home"

_t "2-line PS1, slice 1..1 (most recent)" \
  "$(printf 'two\n❯ echo two')" \
  "$(_mock "$_REV_2LINE" 1 1 '❯')"

_t "2-line PS1, slice 2..2 (oldest)" \
  "$(printf 'one\n❯ echo one')" \
  "$(_mock "$_REV_2LINE" 2 2 '❯')"

_t "2-line PS1, slice 1..2 (both)" \
  "$(printf 'two\n❯ echo two\none\n❯ echo one')" \
  "$(_mock "$_REV_2LINE" 1 2 '❯')"

# ---------------------------------------------------------------------------
# _slice_history — 3-line prompt (extra_lines=2)
# ---------------------------------------------------------------------------
function tmux::_prompt_line_count() { echo 3 }

# 3-line prompt: prompt match, then 2 extra lines after it in reversed stream
_REV_3LINE="beta
❯ echo beta
~/projects
14:30:00
alpha
❯ echo alpha
~/home
09:00:00"

_t "3-line PS1, slice 1..1" \
  "$(printf 'beta\n❯ echo beta')" \
  "$(_mock "$_REV_3LINE" 1 1 '❯')"

_t "3-line PS1, slice 2..2" \
  "$(printf 'alpha\n❯ echo alpha')" \
  "$(_mock "$_REV_3LINE" 2 2 '❯')"

_t "3-line PS1, slice 1..2" \
  "$(printf 'beta\n❯ echo beta\nalpha\n❯ echo alpha')" \
  "$(_mock "$_REV_3LINE" 1 2 '❯')"

# Reset to 1-line prompt
function tmux::_prompt_line_count() { echo 1 }

# ---------------------------------------------------------------------------
# _slice_history — alternate prompt regex (❮ instead of ❯)
# ---------------------------------------------------------------------------
_REV_ALT="world
❮ echo world
hello
❮ echo hello"

_t "alternate prompt_re ❮, slice 1..1" \
  "$(printf 'world\n❮ echo world')" \
  "$(_mock "$_REV_ALT" 1 1 '❮')"

_t "alternate prompt_re ❮, slice 1..2" \
  "$(printf 'world\n❮ echo world\nhello\n❮ echo hello')" \
  "$(_mock "$_REV_ALT" 1 2 '❮')"

# ---------------------------------------------------------------------------
# tmux::cap — argument parsing
# We test by intercepting the pipeline. Mock _slice_history writes to a temp
# file since it runs in a subshell (pipeline).
# ---------------------------------------------------------------------------
local _cap_tmp=$(mktemp)
trap "rm -f '$_cap_tmp'" EXIT

# Save originals
functions -c tmux::_slice_history _orig_slice_history

function tmux::_slice_history() {
  print -r -- "$1 $2" > "$_cap_tmp"
}

# Mock tmux so capture-pane produces empty input
function tmux() { : }

# Remove the TMUX guard for testing
local _orig_cap_body
_orig_cap_body=$(functions tmux::cap)
eval "${_orig_cap_body/\[ -z \"\$TMUX\" \] \&\& return/}"

function _t_cap() {
  local name="$1" exp_from="$2" exp_to="$3"
  shift 3
  if ! _t_should_run "$name"; then
    ((_skip++))
    return
  fi
  if [[ "$_test_list" == "true" ]]; then
    print -r -- "$name"
    return
  fi
  print -r -- "" > "$_cap_tmp"
  tmux::cap "$@" 2>/dev/null
  local result=$(<"$_cap_tmp")
  _t "$name" "${exp_from} ${exp_to}" "$result"
}

# +1 offset applied to skip the tcap command itself
_t_cap "tcap"         2 2
_t_cap "tcap 3"       2 4    3
_t_cap "tcap -2"      3 3    -2
_t_cap "tcap -1"      2 2    -1
_t_cap "tcap -3"      4 4    -3
_t_cap "tcap 1 3"     2 4    1 3
_t_cap "tcap 2 4"     3 5    2 4
_t_cap "tcap 1 1"     2 2    1 1
_t_cap "tcap 3 5"     4 6    3 5
_t_cap "tcap 3 1 (swap)" 2 4  3 1
_t_cap "tcap 5 2 (swap)" 3 6  5 2

# Restore originals
functions -c _orig_slice_history tmux::_slice_history
unset -f _orig_slice_history tmux 2>/dev/null
eval "$_orig_cap_body"

# ---------------------------------------------------------------------------
# End-to-end: simulate the full tac → slice → tac pipeline
# This verifies the final output has prompt BEFORE output (natural order)
# ---------------------------------------------------------------------------
function tmux::_prompt_line_count() { echo 1 }

# Normal scrollback order (as tmux capture-pane would produce)
_SCROLLBACK="❯ echo one
one
❯ echo two
two
❯ echo three
three
❯ echo four
four"

# Helper: run the full tac→slice→tac pipeline on raw scrollback
function _e2e() {
  local scrollback="$1" from="$2" to="$3" re="${4:-❯}"
  print -r -- "$scrollback" | tac | tmux::_slice_history "$from" "$to" "$re" | tac
}

# Most recent command (index 1 in the reversed stream)
_t "e2e: most recent cmd" \
  "$(printf '❯ echo four\nfour')" \
  "$(_e2e "$_SCROLLBACK" 1 1)"

# 2nd most recent
_t "e2e: 2nd most recent" \
  "$(printf '❯ echo three\nthree')" \
  "$(_e2e "$_SCROLLBACK" 2 2)"

# Range: 2 most recent — output is chronological (oldest first) after final tac
_t "e2e: 2 most recent" \
  "$(printf '❯ echo three\nthree\n❯ echo four\nfour')" \
  "$(_e2e "$_SCROLLBACK" 1 2)"

# All 4 — chronological order
_t "e2e: all 4" \
  "$(printf '❯ echo one\none\n❯ echo two\ntwo\n❯ echo three\nthree\n❯ echo four\nfour')" \
  "$(_e2e "$_SCROLLBACK" 1 4)"

# ---------------------------------------------------------------------------
# Edge case: command with no output
# ---------------------------------------------------------------------------
_REV_NOOUT="❯ true
world
❯ echo world"

_t "no-output cmd, slice 1..1" \
  "$(printf '❯ true')" \
  "$(_mock "$_REV_NOOUT" 1 1 '❯')"

_t "no-output cmd, slice 1..2 (includes cmd with output)" \
  "$(printf '❯ true\nworld\n❯ echo world')" \
  "$(_mock "$_REV_NOOUT" 1 2 '❯')"

_t "no-output cmd, slice 2..2 (only cmd with output)" \
  "$(printf 'world\n❯ echo world')" \
  "$(_mock "$_REV_NOOUT" 2 2 '❯')"

# ---------------------------------------------------------------------------
# Edge case: e2e with 2-line prompt
# ---------------------------------------------------------------------------
function tmux::_prompt_line_count() { echo 2 }

_SCROLLBACK_2LINE="~/home
❯ echo one
one
~/projects
❯ echo two
two"

_t "e2e 2-line PS1, most recent" \
  "$(printf '❯ echo two\ntwo')" \
  "$(_e2e "$_SCROLLBACK_2LINE" 1 1)"

_t "e2e 2-line PS1, both" \
  "$(printf '❯ echo one\none\n❯ echo two\ntwo')" \
  "$(_e2e "$_SCROLLBACK_2LINE" 1 2)"

function tmux::_prompt_line_count() { echo 1 }

# ---------------------------------------------------------------------------
# Edge case: output containing backslash sequences and /paths
# The \n in tr "\n" must not be interpreted as a real newline
# ---------------------------------------------------------------------------
_REV_BSLASH=$'has \\n and /paths/to/file\n❯ crontab -l\nother output\n❯ echo hello'

_t 'backslash+slashes, slice 1..1' \
  $'has \\n and /paths/to/file\n❯ crontab -l' \
  "$(_mock "$_REV_BSLASH" 1 1 '❯')"

_t 'backslash+slashes, slice 2..2' \
  $'other output\n❯ echo hello' \
  "$(_mock "$_REV_BSLASH" 2 2 '❯')"

_t 'backslash+slashes, slice 1..2' \
  $'has \\n and /paths/to/file\n❯ crontab -l\nother output\n❯ echo hello' \
  "$(_mock "$_REV_BSLASH" 1 2 '❯')"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print ""
if [[ "$_test_list" == "true" ]]; then
  return 0
fi
local _summary="${_pass} passed, ${_fail} failed"
(( _skip > 0 )) && _summary+=", ${_skip} skipped"
log::info "tmux.test.zsh: ${_summary}"
(( _fail > 0 )) && return 1
return 0
