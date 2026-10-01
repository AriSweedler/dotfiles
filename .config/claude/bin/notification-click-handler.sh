#!/usr/bin/env zsh
#
# Invoked by terminal-notifier -execute when a Claude Code notification is
# clicked (orchestrator). Activates Terminal.app and jumps tmux to the pane
# recorded at fire time.
#
# Args:
#   $1 - tmux target-pane (session:window.pane), optional

set -u

readonly CLAUDE_SCRIPT_ROOT="${0:A:h:h}"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init
  log "i have been clicked"

  local target="${1:-}"
  log "target='${target}'"

  # osascript's activate (~110 ms) and the tmux jump (~30 ms) are independent.
  activate_terminal &
  local activate_pid=$!
  if [[ -n "${target}" ]]; then
    tmux_jump "${target}"
  fi
  wait "${activate_pid}"

  log "end"
}

main "$@"
