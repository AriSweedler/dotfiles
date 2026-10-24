#!/usr/bin/env zsh
#
# Fires a Claude Code notification with a chosen target and message,
# bypassing tmux-pane auto-detection. Useful for testing the click and
# click-simulator pipeline without waiting for Claude Code to emit a real
# Notification event.
#
# Args:
#   $1 - tmux target-pane (session:window.pane), default: current pane
#   $2 - message body, default: "fire-simulator test"

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

main() {
  log_init

  local target="${1:-$(tmux_target_pane)}"
  local msg="${2:-fire-simulator test}"

  log "fire-simulating target='${target}' msg='${msg}'"
  post_notification "${msg}" "${target}"
}

main "$@"
