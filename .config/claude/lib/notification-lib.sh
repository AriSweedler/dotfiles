#!/bin/bash
#
# Implementation layer for the Claude Code notification scripts. Sourced by
# bin/notification.sh, bin/notification-click-handler.sh, and
# bin/notification-click-simulator.sh. Source-only — do not invoke directly.
#
# Caller contract:
#   - Caller MUST set CLAUDE_SCRIPT_ROOT before sourcing (typically derived
#     from "$0"). All paths below are computed relative to that.
#   - Caller MUST call `log_init "$0"` once at start of main().

: "${CLAUDE_SCRIPT_ROOT:?notification-lib: caller must set CLAUDE_SCRIPT_ROOT}"

readonly CLAUDE_BIN_DIR="${CLAUDE_SCRIPT_ROOT}/bin"
readonly CLAUDE_LIB_DIR="${CLAUDE_SCRIPT_ROOT}/lib"

readonly NOTIFIER="/opt/homebrew/bin/terminal-notifier"
readonly TMUX_BIN="/opt/homebrew/bin/tmux"
readonly NOTIFICATION_GROUP="claude-notification"

readonly CLICK_SCRIPT="${CLAUDE_BIN_DIR}/notification-click-handler.sh"
readonly QUICKCHAT_SCRIPT="${CLAUDE_BIN_DIR}/quickchat.sh"
readonly TMUX_PANE_LIB="${CLAUDE_LIB_DIR}/tmux-pane.sh"

readonly LOG_DIR="/tmp/claude-notification"
readonly LAST_TARGET_FILE="${LOG_DIR}/last-target"

# shellcheck source=/dev/null
. "${TMUX_PANE_LIB}"

#######################################
# Sets LOG_FILE to ${LOG_DIR}/<script-basename>.log, ensures the dir exists,
# and truncates the file. Call once at the start of main().
# Arguments:
#   $1 - "$0" from the caller
# Globals:
#   LOG_FILE - set
#######################################
log_init() {
  local script_path="${1:?log_init: pass \"\$0\"}"
  local base="${script_path##*/}"
  LOG_FILE="${LOG_DIR}/${base%.sh}.log"
  mkdir -p "${LOG_DIR}"
  : >"${LOG_FILE}"
}

#######################################
# Appends a timestamped line to LOG_FILE.
#######################################
log() {
  printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"${LOG_FILE}"
}

#######################################
# Persists the most recent tmux target so the click-simulator can find it.
# Arguments:
#   $1 - tmux target-pane (session:window.pane), may be empty
#######################################
record_target() {
  printf '%s' "${1:-}" >"${LAST_TARGET_FILE}"
}

#######################################
# Reads the most recent tmux target. Empty if none recorded.
# Outputs:
#   target string to stdout
#######################################
read_last_target() {
  [[ -f "${LAST_TARGET_FILE}" ]] || return 0
  cat "${LAST_TARGET_FILE}"
}

#######################################
# Brings Terminal.app to the foreground.
#######################################
activate_terminal() {
  /usr/bin/osascript -e 'tell app "Terminal" to activate' >>"${LOG_FILE}" 2>&1
}

#######################################
# Removes the active Claude Code notification from Notification Center.
#######################################
dismiss_notification() {
  "${NOTIFIER}" -remove "${NOTIFICATION_GROUP}" >>"${LOG_FILE}" 2>&1
}

#######################################
# Reports whether a Claude Code notification is currently in Notification
# Center. terminal-notifier -list always exits 0; emptiness is detected by
# the absence of the group ID on a non-header line.
# Returns:
#   0 if a notification is active, 1 if none.
#######################################
notification_is_active() {
  "${NOTIFIER}" -list "${NOTIFICATION_GROUP}" 2>>"${LOG_FILE}" \
    | tail -n +2 \
    | grep -q "^${NOTIFICATION_GROUP}\b"
}

#######################################
# Switches tmux to the target pane (and its window).
# Arguments:
#   $1 - tmux target-pane (session:window.pane)
#######################################
tmux_jump() {
  local target="${1:?tmux_jump: target required}"
  local target_window="${target%.*}"
  "${TMUX_BIN}" select-window -t "${target_window}" \; select-pane -t "${target}" >>"${LOG_FILE}" 2>&1
}

#######################################
# Resolves the notification message body. Source order: stdin JSON .message
# > $1 fallback > random Rocket League quickchat > static placeholder.
# Arguments:
#   $1 - optional fallback message
# Outputs:
#   message string to stdout
#######################################
resolve_message() {
  local msg=""
  if [[ ! -t 0 ]]; then
    msg=$(jq -r '.message // empty' 2>/dev/null || true)
  fi
  if [[ -z "${msg}" && -n "${1:-}" ]]; then
    msg="$1"
  fi
  if [[ -z "${msg}" ]]; then
    msg=$("${QUICKCHAT_SCRIPT}" 2>/dev/null || true)
  fi
  if [[ -z "${msg}" ]]; then
    msg="Claude Code needs your input"
  fi
  printf '%s\n' "${msg}"
}

#######################################
# Posts the notification via terminal-notifier and records the target so
# the click-simulator can find it later. When target is non-empty, wires
# -execute to the click handler; otherwise falls back to -activate.
# Arguments:
#   $1 - message
#   $2 - tmux target-pane (optional)
#######################################
post_notification() {
  local msg="${1:?post_notification: message required}"
  local target="${2:-}"
  record_target "${target}"
  local title="Claude Code"
  if [[ -n "${target}" ]]; then
    local win="${target#*:}"
    title="Claude Code (win${win%%.*})"
  fi
  local -a args=(
    -title "${title}"
    -message "${msg}"
    -sound Glass
    -group "${NOTIFICATION_GROUP}"
  )
  if [[ -n "${target}" ]]; then
    args+=(-execute "${CLICK_SCRIPT} '${target}'")
  else
    args+=(-activate com.apple.Terminal)
  fi
  "${NOTIFIER}" "${args[@]}"
}
