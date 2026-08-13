# Tmux session/window orchestration, sourced by the karabiner-* handlers via REPO_LIB.

function _tsw::session::ensure_create() {
  local session_name="$1"
  local window_name="$2"

  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session already exists | session_name='$session_name'"
    return 0
  fi

  echo "Creating session | session_name='$session_name' $LOG_S"
  tmux new-session -d -s "$session_name" -n "$window_name"
  echo "Session created first window | session_name='$session_name' window_name='$window_name' $LOG_E"
}

# Assumes the session already exists
function _tsw::session::switch() {
  local session_name="$1"

  echo "Switching to session | session_name='$session_name' $LOG_S"
  tmux switch-client -t "$session_name"
  echo "Switched to session | session_name='$session_name' $LOG_E"
}

# Assumes we are already in the correct session
function _tsw::window::ensure_create() {
  local session_name="$1"
  local window_name="$2"

  if tmux list-windows -t "$session_name" -F "#{window_name}" | grep -q "^$window_name$"; then
    echo "Window already exists | session_name='$session_name' window_name='$window_name'"
    return 0
  fi

  echo "Creating window | session_name='$session_name' window_name='$window_name' $LOG_S"
  tmux new-window -t "$session_name" -n "$window_name"
  echo "Window created | session_name='$session_name' window_name='$window_name' $LOG_E"
}

# Assumes we are already in the correct session and the window exists
function _tsw::window::switch() {
  local session_name="$1"
  local window_name="$2"

  echo "Switching to window | session_name='$session_name' window_name='$window_name' $LOG_S"
  tmux select-window -t "$session_name:$window_name"
  echo "Switched to window | session_name='$session_name' window_name='$window_name' $LOG_E"
}

# Assumes we are already in the correct session and window
function _tsw::command::send() {
  local session_name="$1"
  local window_name="$2"
  local command="$3"

  if _tsw::command::send::_should_skip "$session_name" "$window_name"; then
    echo "Skipped command execution | $LOG_E"
    return 0
  fi

  echo "Sending command | session_name='$session_name' window_name='$window_name' command='$command' $LOG_S"
  tmux send-keys -t "$session_name:$window_name" "$command"
  tmux send-keys -t "$session_name:$window_name" Enter
  echo "Command sent | session_name='$session_name' window_name='$window_name' command='$command' $LOG_E"
}

# Skip when the target pane already runs TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION,
# the caller's opt-in guard against re-sending a command into its own editor.
function _tsw::command::send::_should_skip() {
  local session_name="$1"
  local window_name="$2"

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    return 1
  fi

  if ! tmux list-windows -t "$session_name" -F "#{window_name}" | grep -q "^$window_name$"; then
    return 1
  fi

  if [[ -z "$TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION" ]]; then
    return 1
  fi

  local active_app=$(tmux display-message -t "$session_name:$window_name" -p '#{pane_current_command}')
  if [[ "$active_app" != "$TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION" ]]; then
    return 1
  fi

  echo "Recommending skipping send command | active_app='${active_app}' TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION='${TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION}' $LOG_S"
  return 0
}

# Compile a function exported with `export -f` into a one-line string that
# sources its definition from a temp file and then calls it, so tmux
# send-keys can run it in a fresh shell.
function tmux_session_window::cmd::from_exported_fxn() {
  local function_name="${1:?}"

  if ! declare -f "$function_name" >/dev/null 2>&1; then
    echo "ERROR: Function '$function_name' does not exist, did you remember to export it?" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp /tmp/tsw_fxn.XXXXXX)"
  declare -f "$function_name" > "$tmp"
  printf 'source %q && %s\n' "$tmp" "$function_name"
}

# Ensure the session and window exist, focus them, and send the command.
function tmux_session_window::run_cmd() {
  local target_session="${1:?}"
  local target_window="${2:-first-window}"
  local target_command="${3:-echo 'hello world'}"

  local LOG_S="marker='{{{'"
  local LOG_E="marker='}}}'"

  echo "Starting tmux session window command | session_name='$target_session' window_name='$target_window' command='$target_command' $LOG_S"
  _tsw::session::ensure_create "$target_session" "$target_window"
  _tsw::session::switch "$target_session"
  _tsw::window::ensure_create "$target_session" "$target_window"
  _tsw::window::switch "$target_session" "$target_window"
  _tsw::command::send "$target_session" "$target_window" "$target_command"
  echo "Completed tmux session window command | session_name='$target_session' window_name='$target_window' command='$target_command' $LOG_E"
}
