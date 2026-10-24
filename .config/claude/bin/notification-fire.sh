#!/usr/bin/env zsh
#
# Claude Code Notification hook → macOS notification (orchestrator).
# Resolves a message body and the current tmux pane, then posts the
# notification (which also records the target for the click-simulator).

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init

  local msg target
  msg=$(resolve_message "${1:-}")
  target=$(tmux_target_pane)

  log "firing target='${target}' msg='${msg}'"
  post_notification "${msg}" "${target}"
}

main "$@"
