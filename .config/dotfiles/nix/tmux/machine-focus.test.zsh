#!/usr/bin/env zsh
# Tests for .config/dotfiles/nix/tmux/machine-focus.conf: tmux inside tmux, as over ssh, with real
# tmux servers. A third server is the terminal, so the outer tmux has a focused client; the outer
# pane runs a copy of tmux named ssh, so it is the inner client and the outer tmux sees an ssh pane.
# Every server lives under a fresh TMUX_TMPDIR, so no real server is reachable from here.
# Run: zsh ~/dotfiles/.config/dotfiles/nix/tmux/machine-focus.test.zsh
emulate -L zsh
setopt err_return no_unset pipe_fail

CONF=${MACHINE_FOCUS_CONF:-${0:A:h}/machine-focus.conf}   # the file under test
D=$(mktemp -d)
export TMUX_TMPDIR=$D
unset TMUX
IN=$D/in OUT=$D/out TERM_SOCK=$D/term
integer PASS=0 FAIL=0

cleanup() {
  local s
  for s in $TERM_SOCK $OUT $IN; do [[ -S $s ]] && tmux -S $s kill-server 2>/dev/null; done
  rm -rf $D
}
trap cleanup EXIT

ok()   { PASS+=1; print -r -- "  ok   $1"; }
bad()  { FAIL+=1; print -ru2 -- "  FAIL $1"; print -ru2 -- "       $2"; }
check() { [[ $2 == $3 ]] && ok "$1" || bad "$1" "expected: $3 | actual: $2"; }

# wait_until DESC CMD...: poll CMD until it succeeds, up to 3s; a timeout is a failure.
wait_until() {
  local desc=$1; shift
  local i
  for i in {1..30}; do "$@" && { ok "$desc"; return 0 }; sleep 0.1; done
  bad "$desc" "timed out waiting"
}

in_focused()   { [[ $(tmux -S $IN list-clients -F '#{client_flags}') == *focused* ]] }
in_unfocused() { [[ $(tmux -S $IN list-clients -F '#{client_flags}') != *focused* ]] }
# rendered BG: the outer ssh pane, as drawn, holds cells with that 256-colour background
rendered()     { tmux -S $OUT capture-pane -p -e -t $SSH_PANE | grep -q "48;5;$1m\|48;5;$1;" }
not_rendered() { ! rendered $1 }
gopt()         { tmux -S $1 show -gv $2 }
wopt()         { tmux -S $OUT show -wv -t out $1 2>/dev/null || true }

# typhon's two styles, which machine-focus.conf saves and restores
STUB=$D/typhon-stub.conf
print -l 'set -g focus-events on' \
  'set -g window-active-style fg=colour15,bg=colour235' \
  'set -g window-style fg=colour245,bg=colour238' > $STUB
mkdir $D/bin
cp "$(readlink -f "$(command -v tmux)")" $D/bin/ssh

tmux -S $IN -f $STUB new -d -s in -x 100 -y 30
tmux -S $IN source-file $CONF
tmux -S $IN split-window -t in
tmux -S $OUT -f $STUB new -d -s out -x 120 -y 40
tmux -S $OUT source-file $CONF
SSH_PANE=$(tmux -S $OUT split-window -t out -P -F '#{pane_id}' "env -u TMUX $D/bin/ssh -S $IN attach -t in")
LOCAL_PANE=$(tmux -S $OUT list-panes -t out -F '#{pane_id}' | grep -vx $SSH_PANE)
tmux -S $TERM_SOCK -f $STUB new -d -s term -x 130 -y 45 "env -u TMUX tmux -S $OUT attach -t out"

print "setup"
wait_until "outer pane runs ssh" eval '[[ $(tmux -S $OUT display -p -t $SSH_PANE "#{pane_current_command}") == ssh ]]'
wait_until "inner client attached and focused" in_focused

focused_state() {
  check "$1: inner active style is typhon's" "$(gopt $IN window-active-style)" 'fg=colour15,bg=colour235'
  check "$1: inner inactive style is typhon's" "$(gopt $IN window-style)" 'fg=colour245,bg=colour238'
  wait_until "$1: ssh pane draws 235" rendered 235
  wait_until "$1: ssh pane draws no 240" not_rendered 240
  check "$1: outer's other panes are the inactive machine's (243)" "$(wopt window-style)" 'fg=colour245,bg=colour238,bg=colour243'
}
unfocused_state() {
  check "$1: inner active style is 240" "$(gopt $IN window-active-style)" 'fg=colour15,bg=colour235,bg=colour240'
  check "$1: inner inactive style is 243" "$(gopt $IN window-style)" 'fg=colour245,bg=colour238,bg=colour243'
  wait_until "$1: ssh pane draws 240 (inner active pane)" rendered 240
  wait_until "$1: ssh pane draws 243 (inner inactive pane)" rendered 243
  check "$1: outer window style back to typhon's" "$(wopt window-style)" ''
}

# The inner tmux asks for focus reports only once its client is up; on Linux an early focus-out
# can land before that and be lost. Toggle until one arrives, then start from focused.
warm_up() {
  local i
  for i in {1..10}; do
    tmux -S $OUT select-pane -t $LOCAL_PANE; sleep 0.3
    if in_unfocused; then tmux -S $OUT select-pane -t $SSH_PANE; return 0; fi
    tmux -S $OUT select-pane -t $SSH_PANE; sleep 0.3
  done
  return 1
}
warm_up && ok "a focus-out reaches inner" || bad "a focus-out reaches inner" "none in 6s of toggling"
wait_until "initial focus-in reaches inner" in_focused
for round in 1 2 3; do
  print "round $round"
  tmux -S $OUT select-pane -t $LOCAL_PANE
  wait_until "round $round off: inner unfocused" in_unfocused
  unfocused_state "round $round off"
  tmux -S $OUT select-pane -t $SSH_PANE
  wait_until "round $round on: inner focused" in_focused
  focused_state "round $round on"
done

print "conf re-sourced into the inner tmux while it is unfocused"
tmux -S $OUT select-pane -t $LOCAL_PANE
wait_until "inner unfocused" in_unfocused
tmux -S $IN source-file $CONF
check "saved active style is typhon's" "$(gopt $IN @machine-focused-active-style)" 'fg=colour15,bg=colour235'
check "saved inactive style is typhon's" "$(gopt $IN @machine-focused-style)" 'fg=colour245,bg=colour238'
tmux -S $OUT select-pane -t $SSH_PANE
wait_until "inner focused" in_focused
focused_state "after re-source"

print "conf re-sourced into the outer tmux"
tmux -S $OUT source-file $CONF
tmux -S $OUT select-pane -t $LOCAL_PANE
wait_until "inner unfocused" in_unfocused
unfocused_state "after outer re-source"
tmux -S $OUT select-pane -t $SSH_PANE
wait_until "inner focused" in_focused
focused_state "after outer re-source"

print "\n$PASS passed, $FAIL failed"
(( FAIL == 0 ))
