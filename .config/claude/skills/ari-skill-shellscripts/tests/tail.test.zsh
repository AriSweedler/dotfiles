#!/usr/bin/env zsh
# Automated tests for lib/tail.zsh: tail::run's codes and plain streaming, --log, the refusals, and
# the interactive window (TAIL_LINES=4 over a command printing a line every half second for five
# seconds: four lines shown mid-run, then cleared, ✓ and the next line beneath). Run in a tmux pane
# with a terminal, the window draws in that pane and the pane is read back; otherwise (an agent, CI,
# TAIL_TEST_HIDDEN=1) the same run happens on a throwaway tmux server.
# Run: zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/tail.test.zsh
set -uo pipefail

readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB="${SKILLS_DIR}/ari-skill-shellscripts/lib"
source "${LIB}/tail.zsh"
readonly T="${TMPDIR:-/tmp}/tail-test-$$"
readonly SOCK="tail-test-$$"
mkdir -p "${T}"
trap 'tmux -L "${SOCK}" kill-server 2>/dev/null; rm -rf "${T}"' EXIT

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | unwanted='${2}' in='${3}'"; fi
}

# --- plain: streamed, the code passed through, the log kept ---
export TAIL_INTERACTIVE=0
out="$(tail::run --title t -- zsh -c 'print one; print two >&2; exit 3' 2>&1)"; rc=$?
check "plain: the command's code comes back" 3 "${rc}"
contains "plain: stdout streams" one "${out}"
contains "plain: stderr streams" two "${out}"
out="$(tail::run --log "${T}/kept.log" -- zsh -c 'print a; print b' 2>&1)"; rc=$?
check "plain: 0 on success" 0 "${rc}"
check "plain: --log keeps the whole output" $'a\nb' "$(<"${T}/kept.log")"
tail::run --title t 2>/dev/null; rc=$?
check "refused: no command after --" 64 "${rc}"
tail::run --nope -- true 2>/dev/null; rc=$?
check "refused: an unknown flag" 64 "${rc}"
out="$( { tail::start "${T}/kept.log" title; tail::stop; } 2>&1 )"; rc=$?
check "plain: tail::start and tail::stop draw nothing" "" "${out}"
check "plain: tail::start and tail::stop return 0" 0 "${rc}"

# --- interactive: the window, read back from the tmux pane it draws in ---
readonly MARK="ABOVE-$$"
readonly TICKER='for i in {1..10}; do print "line $i"; sleep 0.5; done'

# What the pane shows from the marker line down, mid-run (3.2 s in) and once the ticker is done.
assert_window() {   # <mid capture> <end capture>
  local -a mid_lines=("${(@f)1}") end_lines=("${(@f)2}") shown nums
  local -i at
  at="${mid_lines[(I)${MARK}]}"
  check "mid-run: the line above stays" "${MARK}" "${mid_lines[at]:-}"
  mid_lines=("${(@)mid_lines[at + 1, -1]}")
  shown=(${(M)mid_lines:#  line <->})
  check "mid-run: TAIL_LINES=4 shows exactly four lines" 4 "${#shown}"
  nums=(${shown//  line /})
  check "mid-run: the four are consecutive" "${nums[1]:-} $(( nums[1] + 1 )) $(( nums[1] + 2 )) $(( nums[1] + 3 ))" "${(j: :)nums}"
  lacks "mid-run: the oldest lines have scrolled out" "  line 1|" "${(j:|:)mid_lines}|"
  contains "mid-run: the title shows" ticker "${(F)mid_lines}"
  at="${end_lines[(I)${MARK}]}"
  check "end: ✓ and the title, right under the line above" "✓ ticker" "${end_lines[at + 1]:-}"
  check "end: the next line right under the ✓" NEXT "${end_lines[at + 2]:-}"
  lacks "end: the window is cleared" "  line " "${(F)end_lines[at, -1]}"
}

if ! command -v tmux >/dev/null; then
  print -- "skip    interactive: no tmux"
elif [[ -t 1 && -t 2 && -n "${TMUX_PANE:-}" && "${TAIL_TEST_HIDDEN:-0}" != 1 ]]; then
  # In a terminal: the window draws right here, in this pane, and the pane itself is read back.
  print -- "-- watch: TAIL_LINES=4 over a line every half second for 5 s (TAIL_TEST_HIDDEN=1 hides it)"
  print -- "${MARK}"
  { sleep 3.2; tmux capture-pane -p -t "${TMUX_PANE}" > "${T}/mid"; } &
  capturer=$!
  TAIL_INTERACTIVE=1 TAIL_LINES=4 TAIL_TICK_S=0.1 tail::run --title ticker -- zsh -c "${TICKER}"
  print -- NEXT
  wait "${capturer}"
  sleep 0.2
  tmux capture-pane -p -t "${TMUX_PANE}" > "${T}/end"
  assert_window "$(<"${T}/mid")" "$(<"${T}/end")"
else
  # No terminal (an agent, CI): the same run on a throwaway tmux server.
  cat > "${T}/ticker.zsh" <<EOF
source "${LIB}/tail.zsh"
export TAIL_INTERACTIVE=1 TAIL_LINES=4 TAIL_TICK_S=0.1
print ${MARK}
tail::run --title ticker -- zsh -c ${(q)TICKER}
print NEXT
touch "${T}/done"
sleep 30
EOF
  tmux -L "${SOCK}" new-session -d -x 100 -y 30 "zsh ${T}/ticker.zsh"
  sleep 3.2
  mid="$(tmux -L "${SOCK}" capture-pane -p)"
  for (( i = 0; i < 100; i++ )); do [[ -e "${T}/done" ]] && break; sleep 0.1; done
  sleep 0.3
  assert_window "${mid}" "$(tmux -L "${SOCK}" capture-pane -p)"
fi

print -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
