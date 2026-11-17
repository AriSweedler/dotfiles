#!/usr/bin/env zsh
#
# Claude Code Notification hook → macOS notification (orchestrator).
# Resolves a message body and the current tmux pane, then posts the
# notification (which also records the target for the click-simulator).
# Off macOS there is no Notification Center: the notification is appended to a
# size-capped log instead, and the hook still succeeds. stop-fire.sh calls this
# script, so the same holds at the end of every turn.

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

# The newest 20-30 MB of notifications: 10 MB a file, the live file and two backups.
readonly NOTIFICATIONS_LOG="${XDG_STATE_HOME:-${HOME}/.local/state}/claude/notifications.log"
readonly NOTIFICATIONS_LOG_MAX_BYTES=$(( 10 * 1024 * 1024 ))
readonly NOTIFICATIONS_LOG_FILES=3

#######################################
# Appends one notification, as 'time | host | pane | message', to NOTIFICATIONS_LOG.
# Arguments:
#   $1 - message
#   $2 - tmux target-pane, empty outside tmux
#######################################
record_notification() {
  local msg="${1//$'\n'/ }" target="${2:-no pane}" ts
  strftime -s ts '%Y-%m-%dT%H:%M:%S%z' "${EPOCHSECONDS}"
  log_append_capped "${NOTIFICATIONS_LOG}" "${NOTIFICATIONS_LOG_MAX_BYTES}" "${NOTIFICATIONS_LOG_FILES}" \
    "${ts} | ${HOST} | ${target} | ${msg}"
}

main() {
  local msg target
  msg=$(resolve_message "${1:-}")
  target=$(tmux_target_pane)

  if [[ "${OSTYPE}" != darwin* ]]; then
    record_notification "${msg}" "${target}" || true
    return 0
  fi

  log_init
  log "firing target='${target}' msg='${msg}'"
  post_notification "${msg}" "${target}"
}

main "$@"
