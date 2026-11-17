# Tests for ~/.config/bin/notify off macOS: unread markers (one per pane), count, list, ack,
# the history log, the tmux @notify-unread push under parallel writers, and usage errors. Runs
# against a throwaway state home and its own tmux server, never the live ones. Only runs when
# OTTO_TEST__ZSH_PLUGINS_NOTIFY=true
[[ "$OTTO_TEST__ZSH_PLUGINS_NOTIFY" == "true" ]] || return 0

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

# .config/zsh/plugins/notify.test.zsh → .config/bin/notify, from the checkout under test.
local notify="${0:A:h:h:h}/bin/notify"
local tmp; tmp="$(mktemp -d /tmp/notify.test.XXXXXX)"
local -x XDG_STATE_HOME="${tmp}/state" NOTIFY_PLATFORM=linux TMUX_TMPDIR="${tmp}/tmux"
unset TMUX TMUX_PANE
mkdir -p "${TMUX_TMPDIR}"
tmux -f /dev/null new -d -s notify-test

_t "count: 0 before any" "0" "$(zsh "${notify}" count)"
zsh "${notify}" --title t --pane %3 "first"
zsh "${notify}" --title t --pane %3 "second from the same pane"
zsh "${notify}" --title t --pane %4 "from four"
zsh "${notify}" --title t "no pane"
_t "count: one per pane, and one with none" "3" "$(zsh "${notify}" count)"
_t "tmux: the option follows" "3" "$(tmux show -gv @notify-unread)"
_t "list: a pane's newest replaces its first" "second from the same pane" \
  "$(zsh "${notify}" list | awk -F '\t' '$1 == "pane-3" { print $5 }')"
_t "list: newest first" "no pane" "$(zsh "${notify}" list | head -1 | cut -f5)"
_t "log: every send is history" "4" "$(wc -l < "${XDG_STATE_HOME}/notify/notifications.log" | tr -d ' ')"
zsh "${notify}" ack --pane %3
_t "ack --pane: that pane only" "2" "$(zsh "${notify}" count)"
zsh "${notify}" ack "$(zsh "${notify}" list | awk -F '\t' '$1 == "pane-4" { print $1 }')"
_t "ack ID: that one" "1" "$(zsh "${notify}" count)"
zsh "${notify}" ack
_t "ack: all" "0" "$(zsh "${notify}" count)"
_t "tmux: 0 after ack" "0" "$(tmux show -gv @notify-unread)"

local i
for i in {1..20}; do zsh "${notify}" --pane "%${i}" "p${i}" & done
wait
_t "parallel: every marker" "20" "$(zsh "${notify}" count)"
_t "parallel: the option is the last count, never a stale one" "20" "$(tmux show -gv @notify-unread)"
_t "parallel: no temp file left" "0" "$(ls -A "${XDG_STATE_HOME}/notify/unread" | grep -c '^\.tmp' || true)"

zsh "${notify}" -- list is a message
_t "--: a subcommand word as a message" "list is a message" "$(zsh "${notify}" list | head -1 | cut -f5)"
zsh "${notify}" 2>/dev/null
_t "no message: usage error" "64" "$?"
zsh "${notify}" --nope x 2>/dev/null
_t "unknown flag: usage error" "64" "$?"

tmux kill-server
rm -rf "${tmp}"

if (( _fail == 0 )); then
  log::info "notify.test: all ${_pass} passed"
else
  log::err "notify.test: ${_fail} FAILED, ${_pass} passed"
  return 1
fi
