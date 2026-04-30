#!/bin/bash
#
# Invoked by terminal-notifier -execute when a Claude Code notification is
# clicked (orchestrator). Activates Terminal.app and jumps tmux to the pane
# recorded at fire time.
#
# Args:
#   $1 - tmux target-pane (session:window.pane), optional

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init "$0"
  log "i have been clicked"

  local target="${1:-}"
  log "target='${target}'"

  activate_terminal
  if [[ -n "${target}" ]]; then
    tmux_jump "${target}"
  fi

  log "end"
}

main "$@"
