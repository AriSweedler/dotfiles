#!/usr/bin/env zsh
#
# Programmatically "click" the most recent Claude Code notification
# (orchestrator). Dismisses it from Notification Center and invokes the same
# handler that a real click would. Bind to Raycast / a hotkey to jump to the
# latest waiting Claude without finding the banner.

set -u

readonly CLAUDE_SCRIPT_ROOT="${0:A:h:h}"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init
  log "simulating click"

  local target
  target=$(most_recent_claude_target)
  if [[ -z "${target}" ]]; then
    log "nothing to catch — no active claude-notification"
    return 1
  fi
  log "target='${target}'"

  # The dismissal (~80 ms app launch, occasionally a hang) overlaps the jump
  # instead of delaying it; waited on so it is never orphaned.
  dismiss_notification "${NOTIFICATION_GROUP}-${target}" &
  local dismiss_pid=$!
  "${CLICK_SCRIPT}" "${target}"
  wait "${dismiss_pid}"

  log "end"
}

main "$@"
