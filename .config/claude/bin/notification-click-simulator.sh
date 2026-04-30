#!/bin/bash
#
# Programmatically "click" the most recent Claude Code notification
# (orchestrator). Dismisses it from Notification Center and invokes the same
# handler that a real click would. Bind to Raycast / a hotkey to jump to the
# latest waiting Claude without finding the banner.

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init "$0"
  log "simulating click"

  if ! notification_is_active; then
    log "nothing to catch — no active claude-notification"
    return 1
  fi

  local target
  target=$(read_last_target)
  log "target='${target}'"

  dismiss_notification
  "${CLICK_SCRIPT}" "${target}"

  log "end"
}

main "$@"
