#!/usr/bin/env zsh
#
# Claude Code Notification hook → macOS notification (orchestrator).
# Resolves a message body and the current tmux pane, then posts the
# notification (which also records the target for the click-simulator).

set -u

# Off macOS there is no Notification Center to post to: post nothing and succeed, so the hook
# never fails a turn. stop-fire.sh calls this script, so it is quiet there too.
[[ "${OSTYPE}" == darwin* ]] || exit 0

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
