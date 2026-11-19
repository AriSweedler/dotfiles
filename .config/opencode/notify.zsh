#!/usr/bin/env zsh
#
# OpenCode → macOS notification. The OpenCode side of the agent notification
# system; fired by plugins/opencode-notify/tui.ts when a turn ends, a turn
# fails, or OpenCode asks for permission.
#
# Posts through atn (the logging terminal-notifier front) with the current tmux
# pane as the subtitle, so a click lands back in the pane that needs Ari.
#
# It deliberately posts *into* the Claude Code notification system it sits
# beside: the group, the click handler in ~/.config/claude/bin, and that tree's
# targets.tsv map. That is what makes one hotkey — Hyper+N, or Raycast's "Jump
# to waiting Claude" — jump to whichever agent, Claude or OpenCode, is waiting.
# The shared plumbing wants to move out of ~/.config/claude into a neutral tier;
# until it does, those paths are the contract. Off macOS there is no Notification
# Center: the message goes to ~/.config/bin/notify (Ari's phone) instead.
#
# Usage: notify.zsh <message>

set -u
zmodload zsh/datetime

readonly ATN="${HOME}/.config/bin/atn"
readonly NOTIFY="${HOME}/.config/bin/notify"
readonly CLICK_SCRIPT="${HOME}/.config/claude/bin/notification-click-handler.sh"
readonly NOTIFICATION_GROUP="claude-notification"
readonly TITLE="OpenCode"
readonly LOG_DIR="/tmp/opencode-notification"
readonly LOG_FILE="${LOG_DIR}/notify/log.txt"
# Append-only, rotated by size: this fires on every turn, so a per-run rotation would push the
# previous fire into .bak.1 and leave one line of the only history these checks read.
readonly LOG_MAX_BYTES=$(( 512 * 1024 ))
readonly LOG_KEEP=3
readonly TARGETS_FILE="/tmp/claude-notification/targets.tsv"
# tmux by PATH, else the Nix profiles, else Homebrew's: the TUI may have been
# started by a launcher whose PATH predates any of them.
TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
for _tmux in "/etc/profiles/per-user/${USER:-$(id -un)}/bin/tmux" /run/current-system/sw/bin/tmux /opt/homebrew/bin/tmux; do
  [[ -z "${TMUX_BIN}" && -x "${_tmux}" ]] && TMUX_BIN="${_tmux}"
done
unset _tmux
readonly TMUX_BIN

# log_rotate_at_size, for a log one long-lived writer appends to.
# shellcheck source=/dev/null
. "${HOME}/.config/zsh/plugins/log_rotate.zsh"

#######################################
# Appends a timestamped line to LOG_FILE.
#######################################
log() {
  local ts
  strftime -s ts '%Y-%m-%d %H:%M:%S' "${EPOCHSECONDS}"
  log_rotate_at_size "${LOG_FILE}" "${LOG_MAX_BYTES}" "${LOG_KEEP}"
  zf_mkdir -p "${LOG_FILE:h}" 2>/dev/null
  printf '%s | %s\n' "${ts}" "$*" >>"${LOG_FILE}"
}

#######################################
# Prints the current pane as `session:window.pane`, or nothing outside tmux.
# The plugin's child process inherits TMUX and TMUX_PANE from the TUI, so this
# is the pane the session is actually being driven from.
#######################################
tmux_target_pane() {
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || return 0
  [[ -n "${TMUX_BIN}" ]] || return 0
  "${TMUX_BIN}" display-message -p -t "${TMUX_PANE}" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true
}

#######################################
# Records which tmux target a subtitle names, in the shared map the click simulator reads.
# Append-only: Claude and OpenCode can post within the same millisecond, and a rewrite would drop
# the other's line, leaving a banner that cannot be clicked. The simulator's awk keeps the last row
# per label, so an appended line supersedes an older one. No compaction: this lives in /tmp, costs
# ~60 bytes a turn, and is cleared on reboot.
# Arguments:
#   $1 - subtitle (the pane's name)
#   $2 - tmux target-pane
#######################################
record_target() {
  local label="${1:?}" target="${2:?}"
  zf_mkdir -p "${TARGETS_FILE:h}" 2>/dev/null
  printf '%s\t%s\n' "${label}" "${target}" >>"${TARGETS_FILE}"
}

#######################################
# Posts the notification via atn, with -execute wired to the shared click
# handler when a pane is known and -activate when it is not.
# Arguments:
#   $1 - message
#   $2 - tmux target-pane (optional)
#######################################
post_notification() {
  local msg="${1:?post_notification: message required}"
  local target="${2:-}"
  local label=""
  if [[ -n "${target}" ]]; then
    local window_name panes
    IFS=$'\t' read -r window_name panes < <("${TMUX_BIN}" display-message -p -t "${target}" \
      '#{window_name}	#{window_panes}' 2>/dev/null)
    # Fall back to the window index when the window has no resolvable name.
    if [[ -z "${window_name}" ]]; then
      local win="${target#*:}"
      window_name="win${win%%.*}"
    fi
    label="${window_name}"
    (( ${panes:-1} > 1 )) && label+=" (pane ${target##*.})"
    record_target "${label}" "${target}"
  fi
  local -a args=(
    -title "${TITLE}"
    -message "${msg}"
    -sound Glass
    -group "${NOTIFICATION_GROUP}"
  )
  if [[ -n "${target}" ]]; then
    args+=(-subtitle "${label}" -execute "${CLICK_SCRIPT} '${target}'")
  else
    args+=(-activate com.apple.Terminal)
  fi
  "${ATN}" "${args[@]}"
}

main() {
  # Heartbeat: proves this plugin's TUI part loaded and can reach the script, without waiting for a
  # turn to end. A loaded part with no `firing` lines points at the event name instead.
  case "${1:-}" in
    --loaded)
      log "tui setup pid=$$ ppid=${PPID} pane=${TMUX_PANE:-none}"
      return 0 ;;
  esac

  local msg="${1:-}"
  [[ -n "${msg}" ]] || msg="OpenCode needs your input"
  local target
  target=$(tmux_target_pane)

  if [[ "${OSTYPE}" != darwin* ]]; then
    "${NOTIFY}" --title "${TITLE} on ${HOST}" "${msg} (${target:-no pane})" </dev/null >/dev/null 2>&1 || true
    return 0
  fi

  log "firing target='${target}' msg='${msg}'"
  post_notification "${msg}" "${target}"
}

main "$@"
