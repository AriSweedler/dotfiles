# Transient Notification Center alerts, sourced by the karabiner-* handlers via REPO_LIB.

readonly NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# notify_transient TITLE MESSAGE GROUP [DISMISS_SECS]
# Post an alert that self-dismisses after DISMISS_SECS seconds (default 1).
# The remover is disowned with fds closed so the handler (and anything reading
# its output) never waits out the dismiss window. No-op without terminal-notifier.
notify_transient() {
  local title="${1:?}"
  local message="${2:?}"
  local group="${3:?}"
  local secs="${4:-1}"

  if [[ ! -x "${NOTIFIER}" ]]; then
    return 0
  fi
  "${NOTIFIER}" -title "${title}" -message "${message}" -group "${group}"
  ( sleep "${secs}" && "${NOTIFIER}" -remove "${group}" ) >/dev/null 2>&1 &
  disown
}
