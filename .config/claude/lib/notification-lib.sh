#!/usr/bin/env zsh
#
# Implementation layer for the Claude Code notification scripts. Sourced by
# bin/notification.sh, bin/notification-click-handler.sh, and
# bin/notification-click-simulator.sh. Source-only — do not invoke directly.
#
# Caller contract:
#   - Caller MUST set CLAUDE_SCRIPT_ROOT before sourcing (typically derived
#     from "$0"). All paths below are computed relative to that.
#   - Caller MUST call `log_init` once at start of main().

: "${CLAUDE_SCRIPT_ROOT:?notification-lib: caller must set CLAUDE_SCRIPT_ROOT}"

readonly CLAUDE_BIN_DIR="${CLAUDE_SCRIPT_ROOT}/bin"
readonly CLAUDE_LIB_DIR="${CLAUDE_SCRIPT_ROOT}/lib"
readonly CLICK_SCRIPT="${CLAUDE_BIN_DIR}/notification-click-handler.sh"
readonly QUICKCHAT_SCRIPT="${CLAUDE_BIN_DIR}/quickchat.sh"
readonly TMUX_PANE_LIB="${CLAUDE_LIB_DIR}/tmux-pane.sh"
readonly NOTIFIER="/opt/homebrew/bin/terminal-notifier"
readonly TMUX_BIN="/opt/homebrew/bin/tmux"
readonly NOTIFICATION_GROUP="claude-notification"
readonly LOG_DIR="/tmp/claude-notification"

# shellcheck source=/dev/null
. "${TMUX_PANE_LIB}"

# log_init / log_rotate: per-run logs under $LOG_DIR, rotated (not truncated).
# shellcheck source=/dev/null
. "${HOME}/.config/zsh/plugins/log_rotate.zsh"

#######################################
# Appends a timestamped line to LOG_FILE.
#######################################
log() {
  printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"${LOG_FILE}"
}

#######################################
# Brings Terminal.app to the foreground.
#######################################
activate_terminal() {
  /usr/bin/osascript -e 'tell app "Terminal" to activate' >>"${LOG_FILE}" 2>&1
}

#######################################
# Removes a notification from Notification Center.
# Arguments:
#   $1 - group ID (default: base NOTIFICATION_GROUP)
#######################################
dismiss_notification() {
  local group="${1:-${NOTIFICATION_GROUP}}"
  "${NOTIFIER}" -remove "${group}" >>"${LOG_FILE}" 2>&1
}

#######################################
# Prints the tmux target of the most-recently-delivered active Claude
# notification, or nothing if none. Group IDs use NOTIFICATION_GROUP-<target>
# (per-pane stacking); -list ALL's "Delivered At" column is an ISO-ish
# timestamp that string-sorts chronologically.
# Outputs:
#   target string to stdout, or empty
#######################################
most_recent_claude_target() {
  "${NOTIFIER}" -list ALL 2>>"${LOG_FILE}" \
    | tail -n +2 \
    | awk -F'\t' -v p="${NOTIFICATION_GROUP}-" 'index($1, p) == 1' \
    | sort -t$'\t' -k5,5 -r \
    | head -n 1 \
    | awk -F'\t' -v p="${NOTIFICATION_GROUP}-" '{ sub("^" p, "", $1); print $1 }'
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
# Posts the notification via terminal-notifier with a per-pane group so
# concurrent Claude waits stack in Notification Center instead of dismissing
# each other. When target is non-empty, wires -execute to the click handler;
# otherwise falls back to -activate.
# Arguments:
#   $1 - message
#   $2 - tmux target-pane (optional)
#######################################
post_notification() {
  local msg="${1:?post_notification: message required}"
  local target="${2:-}"
  local group="${NOTIFICATION_GROUP}${target:+-${target}}"
  local title="Claude Code"
  if [[ -n "${target}" ]]; then
    local win="${target#*:}"
    title="Claude Code (win${win%%.*})"
  fi
  local -a args=(
    -title "${title}"
    -message "${msg}"
    -sound Glass
    -group "${group}"
  )
  if [[ -n "${target}" ]]; then
    args+=(-execute "${CLICK_SCRIPT} '${target}'")
  else
    args+=(-activate com.apple.Terminal)
  fi
  "${NOTIFIER}" "${args[@]}"
}
