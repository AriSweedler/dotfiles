#!/usr/bin/env zsh
#
# Idempotent setup for Claude Code notifications:
#   1. Ensures terminal-notifier is installed (via Homebrew).
#   2. Ensures ~/.claude/settings.json's Notification hook points at
#      bin/notification.sh in this directory.
#
# Safe to re-run. Used by ~/.config/new-machine.sh and runnable on demand.

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

readonly CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
readonly NOTIFICATION_SCRIPT="${CLAUDE_BIN_DIR}/notification-fire.sh"

#######################################
# Installs terminal-notifier via Homebrew if not already present.
# Returns:
#   0 on success, 1 if brew is missing or the install failed.
#######################################
ensure_terminal_notifier() {
  if [[ -x "${NOTIFIER}" ]]; then
    log "terminal-notifier present at ${NOTIFIER}"
    return 0
  fi
  log "terminal-notifier missing"
  if ! command -v brew >/dev/null 2>&1; then
    log "brew not found; cannot install terminal-notifier"
    return 1
  fi
  log "installing terminal-notifier via brew"
  brew install terminal-notifier >>"${LOG_FILE}" 2>&1
}

#######################################
# Ensures ${CLAUDE_SETTINGS} has a Notification hook pointing at
# ${NOTIFICATION_SCRIPT}. Creates the file if missing. Uses jq to merge so
# unrelated settings are preserved.
# Returns:
#   0 on success, non-zero on jq failure.
#######################################
ensure_claude_hook() {
  mkdir -p "$(dirname "${CLAUDE_SETTINGS}")"
  if [[ ! -f "${CLAUDE_SETTINGS}" ]]; then
    log "creating ${CLAUDE_SETTINGS}"
    printf '{}\n' >"${CLAUDE_SETTINGS}"
  fi

  local current
  current=$(jq -r '.hooks.Notification[0].hooks[0].command // ""' "${CLAUDE_SETTINGS}" 2>/dev/null || true)
  if [[ "${current}" == "${NOTIFICATION_SCRIPT}" ]]; then
    log "hook already configured"
    return 0
  fi
  log "updating hook: was='${current}' now='${NOTIFICATION_SCRIPT}'"

  local tmp
  tmp=$(mktemp)
  jq --arg cmd "${NOTIFICATION_SCRIPT}" \
    '.hooks.Notification = [{hooks: [{type: "command", command: $cmd}]}]' \
    "${CLAUDE_SETTINGS}" >"${tmp}" && mv "${tmp}" "${CLAUDE_SETTINGS}"
}

main() {
  log_init
  log "initialize start"
  ensure_terminal_notifier || { log "ensure_terminal_notifier failed"; return 1; }
  ensure_claude_hook || { log "ensure_claude_hook failed"; return 1; }
  log "initialize end"
}

main "$@"
