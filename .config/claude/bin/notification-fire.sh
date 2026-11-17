#!/usr/bin/env zsh
#
# Claude Code Notification hook → macOS notification (orchestrator).
# Resolves a message body and the current tmux pane, then posts the
# notification (which also records the target for the click-simulator).
# Off macOS there is no Notification Center: the notification goes to notify
# (~/.config/bin/notify), which pushes it to Ari's phone and logs it, and the hook
# still succeeds. stop-fire.sh calls this script, so the same holds at the end of
# every turn.

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

# By absolute path: the hooks run with Claude's PATH, which may lack ~/.config/bin.
readonly NOTIFY="${HOME}/.config/bin/notify"

main() {
  local msg target
  msg=$(resolve_message "${1:-}")
  target=$(tmux_target_pane)

  if [[ "${OSTYPE}" != darwin* ]]; then
    "${NOTIFY}" --title "Claude Code on ${HOST}" "${msg} (${target:-no pane})" </dev/null >/dev/null 2>&1 || true
    return 0
  fi

  log_init
  log "firing target='${target}' msg='${msg}'"
  post_notification "${msg}" "${target}"
}

main "$@"
