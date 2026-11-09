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
# atn, the shared tier's terminal-notifier logging shim; the hooks run with Claude's PATH, which
# may lack it, hence the absolute path.
readonly NOTIFIER="${HOME}/.config/bin/atn"
readonly CONTENT_IMAGE="${CLAUDE_SCRIPT_ROOT}/assets/claude-code-mascot.png"
# tmux by PATH, else the Nix profiles, else Homebrew's: the hooks run with Claude's PATH,
# which may predate either.
TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
for _tmux in "/etc/profiles/per-user/${USER:-$(id -un)}/bin/tmux" /run/current-system/sw/bin/tmux /opt/homebrew/bin/tmux; do
  [[ -z "${TMUX_BIN}" && -x "${_tmux}" ]] && TMUX_BIN="${_tmux}"
done
unset _tmux
readonly TMUX_BIN
readonly NOTIFICATION_GROUP="claude-notification"
readonly LOG_DIR="/tmp/claude-notification"
# The subtitle shows the pane by name ("nix", "orin (pane 2)"); this file maps each name back to
# its tmux target for the click simulator, one "name<TAB>target" line per name.
readonly TARGETS_FILE="${LOG_DIR}/targets.tsv"

# shellcheck source=/dev/null
. "${TMUX_PANE_LIB}"

# log_init / log_rotate: per-run logs under $LOG_DIR, rotated (not truncated).
# shellcheck source=/dev/null
. "${HOME}/.config/zsh/plugins/log_rotate.zsh"

zmodload zsh/datetime

#######################################
# Appends a timestamped line to LOG_FILE. strftime, not date: every spawn costs
# ~15 ms behind the endpoint agent and the click path logs six lines.
#######################################
log() {
  local ts
  strftime -s ts '%Y-%m-%d %H:%M:%S' "${EPOCHSECONDS}"
  printf '%s | %s\n' "${ts}" "$*" >>"${LOG_FILE}"
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
# notification, or nothing if none. The NOTIFICATION_GROUP row's subtitle ($3)
# names the pane; TARGETS_FILE maps the name back to its target, and a subtitle
# that is already a target (session:window.pane, from before the names) passes
# through. -list ALL's "Delivered At" column ($5) is an ISO-ish timestamp that
# string-compares chronologically. One awk, not a five-process pipeline: each
# spawn costs ~15 ms behind the endpoint agent.
# Outputs:
#   target string to stdout, or empty
#######################################
most_recent_claude_target() {
  "${NOTIFIER}" -list ALL 2>>"${LOG_FILE}" \
    | awk -F'\t' -v g="${NOTIFICATION_GROUP}" -v map="${TARGETS_FILE}" '
        BEGIN { while ((getline line < map) > 0) { split(line, f, "\t"); target_of[f[1]] = f[2] } }
        NR > 1 && $1 == g && $3 != "" && $5 > best { best = $5; label = $3 }
        END {
          if (label in target_of) print target_of[label]
          else if (label ~ /:[0-9]+\.[0-9]+$/) print label
        }'
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
# Records which tmux target a subtitle names, replacing that name's old line.
# Arguments:
#   $1 - subtitle (the pane's name)
#   $2 - tmux target-pane
#######################################
record_target() {
  local label="${1:?}" target="${2:?}" line
  local -a kept=()
  if [[ -f "${TARGETS_FILE}" ]]; then
    while IFS= read -r line; do
      [[ "${line%%$'\t'*}" == "${label}" ]] || kept+=("${line}")
    done < "${TARGETS_FILE}"
  fi
  mkdir -p "${LOG_DIR}"
  print -rl -- "${kept[@]}" "${label}"$'\t'"${target}" >| "${TARGETS_FILE}"
}

#######################################
# Posts the notification via terminal-notifier. One group for every Claude
# notification: terminal-notifier 3.x makes the group the Notification Center
# stack, so per-pane groups would scatter them; the pane travels in the
# subtitle instead, and a newer wait replaces the banner of an older one. When
# target is non-empty, wires -execute to the click handler; otherwise falls
# back to -activate.
# Arguments:
#   $1 - message
#   $2 - tmux target-pane (optional)
#######################################
post_notification() {
  local msg="${1:?post_notification: message required}"
  local target="${2:-}"
  local title="Claude Code" label=""
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
    -title "${title}"
    -message "${msg}"
    -sound Glass
    -group "${NOTIFICATION_GROUP}"
    -contentImage "${CONTENT_IMAGE}"
  )
  if [[ -n "${target}" ]]; then
    args+=(-subtitle "${label}" -execute "${CLICK_SCRIPT} '${target}'")
  else
    args+=(-activate com.apple.Terminal)
  fi
  [[ -f "${CONTENT_IMAGE}" ]] || log "WARN notification -contentImage is not a file | path='${CONTENT_IMAGE}'"
  "${NOTIFIER}" "${args[@]}"
}
