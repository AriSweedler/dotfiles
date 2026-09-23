#!/usr/bin/env zsh
#
# Idempotent setup for the Claude Code hooks this directory provides:
#   1. Ensures terminal-notifier is installed (via Homebrew).
#   2. Ensures ~/.claude/settings.json's Notification hook points at
#      bin/notification-fire.sh in this directory.
#   3. Ensures ~/.claude/settings.json has a PreToolUse (Bash) hook running
#      bin/pretooluse-headless-chrome-guard.sh, gated to commands that mention
#      --headless.
#
# Safe to re-run. Used by `new-machine setup` and runnable on demand.

set -u

readonly CLAUDE_SCRIPT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${CLAUDE_SCRIPT_ROOT}/lib/notification-lib.sh"

readonly CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
readonly NOTIFICATION_SCRIPT="${CLAUDE_BIN_DIR}/notification-fire.sh"
readonly GUARD_SCRIPT="${CLAUDE_BIN_DIR}/pretooluse-headless-chrome-guard.sh"
# Claude Code only spawns the hook for Bash commands matching this rule, so
# ordinary commands pay nothing for it.
readonly GUARD_IF='Bash(*--headless*)'

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

#######################################
# Ensures ${CLAUDE_SETTINGS} has a PreToolUse hook (matcher Bash) running
# ${GUARD_SCRIPT}. Other PreToolUse entries are kept; an entry for this script
# is rewritten in place when its shape drifts.
# Returns:
#   0 on success, non-zero on jq failure.
#######################################
ensure_headless_chrome_guard() {
  local want current
  want=$(jq -nc --arg cmd "${GUARD_SCRIPT}" --arg if "${GUARD_IF}" \
    '{matcher: "Bash", hooks: [{type: "command", command: $cmd, if: $if, timeout: 5}]}')
  current=$(jq -c --arg cmd "${GUARD_SCRIPT}" \
    '[.hooks.PreToolUse // [] | .[] | select(any(.hooks[]?; .command == $cmd))] | first // empty' \
    "${CLAUDE_SETTINGS}" 2>/dev/null || true)
  if [[ "${current}" == "${want}" ]]; then
    log "guard hook already configured"
    return 0
  fi
  log "updating guard hook: was='${current}' now='${want}'"

  local tmp
  tmp=$(mktemp)
  jq --arg cmd "${GUARD_SCRIPT}" --argjson want "${want}" \
    '.hooks.PreToolUse = ([.hooks.PreToolUse // [] | .[] | select(any(.hooks[]?; .command == $cmd) | not)] + [$want])' \
    "${CLAUDE_SETTINGS}" >"${tmp}" && mv "${tmp}" "${CLAUDE_SETTINGS}"
}

main() {
  log_init
  log "initialize start"
  ensure_terminal_notifier || { log "ensure_terminal_notifier failed"; return 1; }
  ensure_claude_hook || { log "ensure_claude_hook failed"; return 1; }
  ensure_headless_chrome_guard || { log "ensure_headless_chrome_guard failed"; return 1; }
  log "initialize end"
}

main "$@"
