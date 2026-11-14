#!/usr/bin/env zsh
# Automated tests for lib/await.zsh: the guard's endings, await::run's codes (0, rc, 124, 130),
# the refusal of a helper outside a wait, nested waits, plain and interactive renderings, slots,
# notes, the step's stderr relayed above the line, the style check, await::until's probe
# protocol, the step's whole process tree killed on a timeout and a ctrl-c, and one wait primitive
# per run with and without zsh/zselect. No tty needed; the ctrl-c test needs perl.
# Run: zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/await.test.zsh
set -uo pipefail

readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB="${SKILLS_DIR}/ari-skill-shellscripts/lib"
source "${LIB}/logging.zsh"
source "${LIB}/await.zsh"
export AWAIT_INTERACTIVE=0 AWAIT_TICK_S=0.01 LOG_COLOR=0
readonly T="${TMPDIR:-/tmp}/await-test-$$"
mkdir -p "${T}"
# The tree tests' sleeps last <n>.<this run's pid> s: no other process, a concurrent run of this
# file included, has that command line, and a failing run must not leave one behind.
readonly TREE_SLEEPS="^sleep 3[0-9]\\.$$\$"
trap 'pkill -f "${TREE_SLEEPS}"; rm -rf "${T}"' EXIT
alive() { pgrep -f "^sleep ${1//./\\.}\$" | wc -l | tr -d ' '; }   # <seconds>: how many such sleeps run
export TMPDIR="${T}"      # every channel and fifo of this run lands here, so the leftover checks see no other process's wait

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
count() { print -r -- "${2}" | grep -c -- "${1}" | tr -d ' '; }

# 1. every helper outside a wait is refused with 2 and the one message
for h in computer user progress note success failure; do
  err="$( await::${h} 1 2>&1 )"; rc=$?
  check "await::${h} outside a wait returns 2" 2 "${rc}"
  contains "await::${h} outside a wait says YOU MUST CALL" "YOU MUST CALL await::${h} INSIDE await::run OR await::_guard (AWAIT_FD is unset)" "${err}"
done

# 2. the guard ends with the function: ✓ on 0, ✗ with the code, the args shown
guarded() {
  await::_guard "frobbing the widget…" -- "$@"
  await::computer "more"; {
    :
  }
  return "${1}"
}
err="$( guarded 0 foo 2>&1 )"; rc=$?
check "guard: return 0 is 0" 0 "${rc}"
contains "guard: ✓ line carries the message" "[AWAIT] ✓ success: frobbing the widget…" "${err}"
contains "guard: the opening line shows the args" "computer: frobbing the widget… | elapsed_s='0' | args='0 foo'" "${err}"
check "guard: exactly one ending" 1 "$(count 'success\|failure' "${err}")"
err="$( guarded 3 bar 2>&1 )"; rc=$?
check "guard: return 3 is 3" 3 "${rc}"
contains "guard: ✗ line shows rc and args" "[AWAIT] ✗ failure: frobbing the widget… | elapsed_s='0' | rc='3' | args='3 bar'" "${err}"
err="$( guarded 130 2>&1 )"; rc=$?
check "guard: 130 passes through" 130 "${rc}"
contains "guard: 130 reads as interrupted" "✗ failure: interrupted: frobbing the widget…" "${err}"
check "AWAIT_FD is unset after the wait" "" "${AWAIT_FD:-}"
leftovers=("${TMPDIR:-/tmp}"/await.*(N))
check "no channel is left behind" 0 "${#leftovers}"

# 3. endings by hand: the hand ending stands, the return only reaps
by_hand() { await::_guard "m" -- ; await::success "done by hand"; return "${1}"; }
err="$( by_hand 0 2>&1 )"; rc=$?
check "hand success then return 0" 0 "${rc}"
check "hand success is the only ending" 1 "$(count 'success\|failure' "${err}")"
contains "hand success message" "✓ success: done by hand" "${err}"
err="$( by_hand 5 2>&1 )"; rc=$?
check "hand success then return 5 keeps 5" 5 "${rc}"
check "hand success then return 5 still ends once" 1 "$(count 'success\|failure' "${err}")"
fail_hand() { await::_guard "m" -- ; await::failure "nope" 7; }
err="$( fail_hand 2>&1 )"; rc=$?
check "hand failure returns its rc" 7 "${rc}"
contains "hand failure line" "✗ failure: nope | elapsed_s='0' | rc='7'" "${err}"

# 4. nested waits: the outer freezes, the inner draws one space in, the outer resumes
sub() { sleep 0.2; return "${1}"; }
nest_step() { await::run "inner" -- sub "${1}"; print -r -- "inner rc=$?"; return 0; }
out="$( await::run "outer" -- nest_step 0 2>"${T}/nest.err" )"; rc=$?
err="$(<"${T}/nest.err")"
check "nested: outer returns its own code" 0 "${rc}"
contains "nested: the inner's code reaches the outer step" "inner rc=0" "${out}"
check "nested: inner lines are indented by exactly one space" 2 "$(count '^ \[AWAIT\]' "${err}")"
check "nested: outer lines are not indented" 2 "$(count '^\[AWAIT\]' "${err}")"
check "nested: plain order is outer, inner, inner ✓, outer ✓" "computer: outer|computer: inner|✓ success: inner|✓ success: outer" \
  "$(print -r -- "${err}" | grep AWAIT | sed -E 's/^ *\[AWAIT\] //; s/ \| .*//' | paste -sd '|' -)"
out="$( await::run "outer" -- nest_step 3 2>"${T}/nest.err" )"; rc=$?
err="$(<"${T}/nest.err")"
check "nested: an inner failure leaves the outer at 0" 0 "${rc}"
contains "nested: the inner failure reaches the outer step" "inner rc=3" "${out}"
contains "nested: the inner ✗ line is indented and carries its rc" " [AWAIT] ✗ failure: inner | elapsed_s='0' | rc='3' | args='sub 3'" "${err}"
contains "nested: the outer still ends ✓" $'\n[AWAIT] ✓ success: outer' "${err}"
deep() { await::run "level two" -- sleep 0.1; }
mid() { await::run "level one" -- deep; }
err="$( await::run "top" -- mid 2>&1 )"; rc=$?
check "nested twice: 0" 0 "${rc}"
check "nested twice: level two is indented by two spaces" 2 "$(count '^  \[AWAIT\].*level two' "${err}")"
check "nested twice: level one by one" 2 "$(count '^ \[AWAIT\].*level one' "${err}")"
check "AWAIT_DEPTH is gone after the outermost wait" "" "${AWAIT_DEPTH:-}"
raw="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run "outer" -- nest_step 0 2>&1 >/dev/null )"
lines=("${(@f)raw}")
check "nested interactive: three lines, frozen outer, inner, resumed outer" 3 "${#lines}"
check "nested interactive: the frozen outer line is left without a final glyph" 1 "$([[ "${lines[1]}" == *outer* && "${lines[1]}" != *✓* ]] && print 1 || print 0)"
check "nested interactive: the inner line is one space in and ends ✓" 1 "$([[ "${lines[2]}" == *$'\r '*'✓'*inner* ]] && print 1 || print 0)"
check "nested interactive: the outer resumes and ends ✓ on its own line" 1 "$([[ "${lines[3]}" == *$'\r'[^\ ]*outer*✓*outer* ]] && print 1 || print 0)"

# 5. the grammar
err="$( bad_grammar() { await::_guard "no dashes" ; }; bad_grammar 2>&1 )"; rc=$?
contains "guard without -- is refused" "the grammar is" "${err}"
err="$( await::run "m" true 2>&1 )"; rc=$?
check "run without -- is 2" 2 "${rc}"
err="$( await::run --bogus 1 "m" -- true 2>&1 )"; rc=$?
check "run with an unknown flag is 2" 2 "${rc}"

# 6. await::run: the step's code, a timeout, slots, notes, the order of plain lines
err="$( await::run "m" -- true 2>&1 )"; rc=$?
check "run true is 0" 0 "${rc}"
err="$( await::run "m" -- sh -c 'exit 5' 2>&1 )"; rc=$?
check "run passes the step's code" 5 "${rc}"
contains "run shows the command as args" "args='sh -c exit 5'" "${err}"
t0=${EPOCHREALTIME}
err="$( await::run --timeout 0.3 "m" -- sleep 60 2>&1 )"; rc=$?
check "run --timeout is 124" 124 "${rc}"
contains "run --timeout reads as timed out" "✗ failure: timed out: m" "${err}"
check "run --timeout killed the step" 1 "$(( EPOCHREALTIME - t0 < 3 ))"
# Work after the command keeps the step's subshell alive with the sleep as its child; a step whose
# last command is the sleep is exec'd in its place, and this would pass on a lib that kills only it.
tree_step() { sleep "31.$$"; true; }
for mode in 0 1; do
  AWAIT_INTERACTIVE="${mode}" AWAIT_BELL=0 await::run --timeout 0.3 "m" -- tree_step 2>/dev/null; rc=$?   # a test silences a wait; a script never does
  check "run --timeout (interactive=${mode}) on a function step is 124" 124 "${rc}"
  check "run --timeout (interactive=${mode}) leaves no process of the step" 0 "$(alive "31.$$")"
  pkill -f "^sleep 31\\.$$\$"
done
# A timeout on an outer wait kills the open inner wait with its step: the outer still ends ✗.
nest_tree() { await::run "inner" -- tree_step; true; }
mkdir -p "${T}/nest-cut"
err="$( TMPDIR="${T}/nest-cut" await::run --timeout 0.5 "outer" -- nest_tree 2>&1 )"; rc=$?
check "nested, outer --timeout: 124" 124 "${rc}"
contains "nested, outer --timeout: the outer still ends ✗ timed out" $'\n[AWAIT] ✗ failure: timed out: outer' "${err}"
check "nested, outer --timeout: no process of either step is left" 0 "$(alive "31.$$")"
pkill -f "^sleep 31\\.$$\$"
talks() {
  await::computer "one"; {
    :
  }
  await::user "two"; {
    :
  }
  await::note "a note"
  await::computer "three"; {
    :
  }
  await::progress 2
}
err="$( await::run --slots 3 "m" -- talks 2>&1 )"; rc=$?
lacks "a conforming fixture raises no style warning" "style:" "${err}"
check "run with a talking step is 0" 0 "${rc}"
check "plain: one line per change, in order" "computer 0/3: m|computer 0/3: one|user 0/3: two|note|computer 0/3: three|computer 2/3: three|success 3/3: m" \
  "$(print -r -- "${err}" | grep AWAIT | sed -E 's/^\[AWAIT\] (✓ |✗ )?//; s/ \| .*//; s/: a note//' | paste -sd '|' -)"
contains "plain: the note line" "[AWAIT] note: a note" "${err}"
clamp() { await::progress 9; }
err="$( await::run --slots 3 "m" -- clamp 2>&1 )"
contains "progress clamps to the slot count" "computer 3/3: m" "${err}"

# 7. interactive rendering, forced on a pipe
shows() {
  await::computer "work"; {
    sleep 0.25
  }
  await::progress 1
  await::user "you"; {
    sleep 0.25
  }
}
out="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run --slots 2 "m" -- shows 2>&1 )"
contains "interactive draws slots" "[" "${out}"
check "interactive draws a spinner frame" 1 "$([[ "${out}" == *[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]* ]] && print 1 || print 0)"
contains "interactive draws the pulse" "◆" "${out}"
contains "interactive ends with the check mark" "✓ m" "${out}"
check "interactive redraws with carriage returns" 1 "$([[ "${out}" == *$'\r'* ]] && print 1 || print 0)"
out="$( { AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run "m" -- true; print -nu2 END; } 2>&1 )"
check "interactive final line ends with a newline" 1 "$([[ "${out}" == *$'\n'END ]] && print 1 || print 0)"
rings() {
  await::user "a"; {
    :
  }
  await::user "b"; {
    :
  }
}
out="$( AWAIT_INTERACTIVE=1 await::run "m" -- rings 2>&1 )"
check "entering user rings once when interactive" 1 "$(print -rn -- "${out}" | tr -cd '\a' | wc -c | tr -d ' ')"
out="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run "m" -- rings 2>&1 )"
check "AWAIT_BELL=0 silences it" 0 "$(print -rn -- "${out}" | tr -cd '\a' | wc -c | tr -d ' ')"
err="$( AWAIT_INTERACTIVE=1 guarded 4 x 2>&1 )"
contains "interactive ✗ shows the args" "args='4 x'" "${err}"

# 8. the step's stderr: relayed above the line when interactive, passed through when plain; the probe's too
clear=$'\e[K'
logs() { print -u2 "[INFO] copying | rel='a.gcode'"; sleep 0.15; print -u2 "  second line, indented"; sleep 0.15; }
raw="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run --slots 1 "copying…" -- logs 2>&1 >/dev/null )"
lines=("${(@f)raw}")
check "interactive: a step's two stderr lines each get a line, then the ✓ line" 3 "${#lines}"
check "interactive: the first stderr line is whole on its own line" "[INFO] copying | rel='a.gcode'" "${lines[1]##*${clear}}"
check "interactive: the second keeps its leading spaces" "  second line, indented" "${lines[2]##*${clear}}"
check "interactive: the ✓ line comes last" 1 "$([[ "${lines[3]}" == *'✓'*copying* && "${lines[3]}" != *second* ]] && print 1 || print 0)"
check "interactive: one slot draws the slot cell and the frame, both spinning" 1 "$([[ "${raw}" == *'['[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]']'*' '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]' copying'* ]] && print 1 || print 0)"
err="$( await::run "copying…" -- logs 2>&1 )"
contains "plain: the step's stderr passes through as it came" $'\n[INFO] copying | rel=\'a.gcode\'\n  second line, indented\n' "${err}"
lacks "plain: the step's stderr is not rewritten as a note" "[AWAIT] note" "${err}"
check "plain: the ✓ line still comes last" 1 "$([[ "${err}" == *"second line, indented"*'✓ success: copying'* ]] && print 1 || print 0)"
chatty() { while true; do print -u2 tick; sleep 0.05; done; }
raw="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run --timeout 0.3 "m" -- chatty 2>&1 >/dev/null )"; rc=$?
check "interactive: a chatty step killed by --timeout is 124" 124 "${rc}"
check "interactive: its ticks precede the ✗ line, which is last" 1 "$([[ "${raw}" == *tick*'✗'*'timed out: m'* && "${raw##*timed out}" != *tick* ]] && print 1 || print 0)"
leftovers=("${TMPDIR:-/tmp}"/await.*(N))
check "interactive: no fifo is left behind after the relay" 0 "${#leftovers}"
probe_logs() { print -u2 "probe looked"; print "success seen"; }
raw="$( AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::until --timeout 5 -- probe_logs 2>&1 )"; rc=$?
lines=("${(@f)raw}")
check "until interactive: the probe's stderr is a line above, then the ✓ line" 2 "${#lines}"
check "until interactive: the probe's line is whole" "probe looked" "${lines[1]##*${clear}}"
check "until interactive: the ✓ line comes last" 1 "$([[ "${lines[2]}" == *'✓'*seen* ]] && print 1 || print 0)"
out="$( await::until --timeout 5 -- probe_logs 2>&1 )"
contains "until plain: the probe's stderr passes through before its state" $'probe looked\n[AWAIT] ✓ success: seen' "${out}"
orphan() { ( sleep 1.5; print -u2 "late line" ) & print -u2 "step line"; }
t0=${EPOCHREALTIME}
AWAIT_INTERACTIVE=1 AWAIT_BELL=0 await::run "m" -- orphan 2>"${T}/orphan.err" >/dev/null; rc=$?
elapsed=$(( EPOCHREALTIME - t0 ))
check "interactive: a step that leaves a child holding stderr still ends 0" 0 "${rc}"
check "interactive: its ✓ waits about a second for that child, not for its exit" 1 "$(( elapsed >= 0.9 && elapsed < 1.5 ))"
sleep 1
raw="$(<"${T}/orphan.err")"
check "interactive: the child's later line prints under the ✓, and the child lives" 1 "$([[ "${raw%%late line*}" == *'✓'* && "${raw}" == *'late line'* ]] && print 1 || print 0)"
inner_refused() { TMPDIR="${T}/nope" await::run "inner" -- true; print -r -- "inner rc=$?"; }
out="$( await::run "outer" -- inner_refused 2>"${T}/refused.err" )"; rc=$?
err="$(<"${T}/refused.err")"
contains "a refused inner wait (no TMPDIR) returns 2 to the step" "inner rc=2" "${out}"
check "a refused inner wait leaves the outer at 0" 0 "${rc}"
contains "a refused inner wait still lets the outer end ✓" "✓ success: outer" "${err}"

# 9. await::until: the probe's words rule
counter="${T}/counter"; print 0 > "${counter}"
probe_counts() {
  local calls=$(( $(<"${counter}") + 1 )); print "${calls}" > "${counter}"
  if (( calls < 3 )); then print "computer frobbing the widget ${calls}"
  elif (( calls == 3 )); then print "user press the thing"
  else print "progress 1"; print "success it worked"; fi
}
out="$( await::until --slots 1 --timeout 5 -- probe_counts 2>&1 )"; rc=$?
lacks "until's relay raises no style warning" "style:" "${out}"
check "until returns 0 on success" 0 "${rc}"
contains "until relayed the computer state" "computer 0/1: frobbing the widget 1" "${out}"
contains "until relayed the user state" "user 0/1: press the thing" "${out}"
contains "until relayed progress then success" "success 1/1: it worked" "${out}"
probe_fails() { print "failure nope"; }
out="$( await::until --timeout 5 -- probe_fails 2>&1 )"; rc=$?
check "until returns 1 on failure" 1 "${rc}"
probe_never() { print "computer forever"; }
out="$( await::until --timeout 0.05 --interval 0.01 -- probe_never 2>&1 )"; rc=$?
check "until returns 124 at the timeout" 124 "${rc}"
contains "until names the timeout" "failure: timed out" "${out}"
probe_bad() { print "sleeping zzz"; }
out="$( await::until --timeout 5 -- probe_bad 2>&1 )"; rc=$?
check "until returns 2 on an unknown state" 2 "${rc}"
contains "until lists the states it knows" "states='computer, user, success, failure, progress'" "${out}"
out="$( await::until 2>&1 )"; rc=$?
check "until without a probe is 2" 2 "${rc}"
out="$( await::until --bogus 1 --timeout 5 -- probe_fails 2>&1 )"; rc=$?
check "until refuses an unknown flag with 2" 2 "${rc}"

# 10. ctrl-c during await::run ends as 130 and kills the step's whole tree, in a child shell. A
# terminal's ctrl-c is INT to the foreground process group, so the child gets a group of its own
# (perl's setpgrp; `set -m` needs a tty) and INT back at its default (a `&` job starts with it
# ignored, and a shell cannot trap a signal ignored at entry). The step's subshell and its sleep
# ignore INT as every background job here does: only the library's kill ends them.
cat > "${T}/int.zsh" <<'CHILD'
set -euo pipefail
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/await.zsh"
(( ${STUBBORN:-0} )) && trap '' TERM    # the step and its sleep ignore TERM too: only the KILL ends them
step() { sleep "${SLEEP_S}"; true; }
AWAIT_INTERACTIVE=0 await::run "m" -- step
CHILD
if command -v perl >/dev/null; then
  # A second ctrl-c 0.1 s after the first lands inside the TERM grace; it must not cut the cleanup short.
  for stubborn in 0 1; do
    if (( stubborn )); then name="ctrl-c twice on a step that ignores TERM"; else name="ctrl-c in run"; fi
    secs="32.$$"; dir="${T}/int-${stubborn}"; mkdir -p "${dir}"
    STUBBORN="${stubborn}" SLEEP_S="${secs}" TMPDIR="${dir}" \
      perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' zsh "${T}/int.zsh" 2>"${dir}/err" &
    child=$!
    for (( i = 0; i < 50; i++ )); do    # the step's sleep runs once the wait is open and its INT trap armed
      [[ "$(alive "${secs}")" != 0 ]] && break
      sleep 0.1
    done
    kill -s INT -- "-${child}"
    if (( stubborn )); then sleep 0.1; kill -s INT -- "-${child}" 2>/dev/null; fi
    rc=0; wait "${child}" || rc=$?
    check "${name}: 130" 130 "${rc}"
    contains "${name}: reported as interrupted" "✗ failure: interrupted: m" "$(<"${dir}/err")"
    check "${name}: no process of the step is left" 0 "$(alive "${secs}")"
    leftovers=("${dir}"/await.*(N))
    check "${name}: no channel is left behind" 0 "${#leftovers}"
    pkill -f "^sleep 32\\.$$\$"
  done
else
  check "ctrl-c in run: perl is on PATH (it gives the child its own process group)" perl ''
fi

# 11. the style check: a state call wants `; {` on its line or `{` on the next
cat > "${T}/style.zsh" <<'FIX'
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/await.zsh"
export AWAIT_INTERACTIVE=0 LOG_COLOR=0
good() {
  await::user "same line"; {
    :
  }
  await::computer "next line"   # a comment
  {
    :
  }
}
bad() {
  await::user "no block"
}
await::run "m" -- good
await::run "m" -- bad
await::run "m" -- bad
FIX
err="$( zsh "${T}/style.zsh" 2>&1 )"
check "style: conforming sites raise no warning" 0 "$(count 'same line\|next line' "$(print -r -- "${err}" | grep WARN)")"
check "style: a bare state call warns once per site, even when called twice" 1 "$(count 'style: await::user should be followed by an indented { } group' "${err}")"
contains "style: the warning names the call site" "at='${T}/style.zsh:14'" "${err}"
err="$( zsh -c 'source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"; source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/await.zsh"; export AWAIT_INTERACTIVE=0; s() { await::user "x"; }; await::run "m" -- s' 2>&1 )"
lacks "style: no warning from zsh -c" "style:" "${err}"

# 12. one wait primitive per run, chosen at load: zselect when zsh/zselect works, else sleep and
# `read -t`. Each child logs every call to the primitive it must not use; a stub zselect defined
# before the lib loads stands in for a zsh without the module.
cat > "${T}/prim.zsh" <<'CHILD'
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
(( NO_ZSELECT )) && zselect() { print -r -- zselect >> "${PRIM_LOG}"; return 2; }
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/await.zsh"
(( NO_ZSELECT )) || sleep() { print -r -- sleep >> "${PRIM_LOG}"; command sleep "$@"; }
: > "${PRIM_LOG}"
export AWAIT_BELL=0
step() { command sleep 0.5; true; }
long() { command sleep "${SLEEP_S}" </dev/null >/dev/null 2>&1; true; }   # no pipe of ours stays open behind it
probe() { print "success seen"; }
t0=${EPOCHREALTIME}
AWAIT_INTERACTIVE=0 await::run "plain" -- step; print -r -- "plain rc=$? wall=$(( EPOCHREALTIME - t0 ))"
AWAIT_INTERACTIVE=1 await::run "drawn" -- step; print -r -- "drawn rc=$?"
AWAIT_INTERACTIVE=0 await::run --timeout 0.3 "cut" -- long; rc=$?
print -r -- "cut rc=${rc} alive=$(pgrep -f "^sleep ${SLEEP_S//./\\.}\$" | wc -l | tr -d ' ')"
AWAIT_INTERACTIVE=0 await::until --interval 0.05 --timeout 5 -- probe; print -r -- "until rc=$?"
CHILD
for no_zselect in 0 1; do
  if (( no_zselect )); then used=sleep unused=zselect; else used=zselect unused=sleep; fi
  print -n > "${T}/prim.log"
  out="$( NO_ZSELECT="${no_zselect}" PRIM_LOG="${T}/prim.log" SLEEP_S="33.$$" zsh "${T}/prim.zsh" 2>"${T}/prim.err" )"
  err="$(<"${T}/prim.err")"
  wall="${${out#*wall=}%%$'\n'*}"
  check "${used}: no ${unused} call once the lib has loaded" "" "$(<"${T}/prim.log")"
  contains "${used}: a plain run of a 0.5 s step is 0" "plain rc=0" "${out}"
  contains "${used}: its ✓ line prints" "[AWAIT] ✓ success: plain" "${err}"
  check "${used}: it takes under 2 s (each tick waits once; the doubled ticks took 2.7 s)" 1 "$(( ${wall:-9} < 2.0 ))"
  contains "${used}: an interactive run is 0" "drawn rc=0" "${out}"
  contains "${used}: its ✓ line prints" "✓ drawn" "${err}"
  contains "${used}: --timeout is 124" "cut rc=124" "${out}"
  contains "${used}: --timeout leaves no process of the step" "alive=0" "${out}"
  contains "${used}: await::until is 0" "until rc=0" "${out}"
  pkill -f "^sleep 33\\.$$\$"
done

print
print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
