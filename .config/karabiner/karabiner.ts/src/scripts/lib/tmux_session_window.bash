# Tmux Session/Window Management Framework
# This script demonstrates the high-level flow:
# 1. Session Management - ensure we're in the right session
# 2. Window Management - ensure we're in the right window
# 3. Command Execution - send arbitrary commands

function _tsw::session::ensure_create() {
  local session_name="$1"
  local window_name="$2"

  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session already exists | session_name='$session_name'"
    return 0
  fi

  echo "Creating session | session_name='$session_name' $LOG_S"
  tmux new-session -d -s "$session_name"
  local first_window=$(tmux list-windows -t "$session_name" -F "#{window_index}" | head -1)
  tmux rename-window -t "$session_name:$first_window" "$window_name"
  echo "Session created first window | session_name='$session_name' window_name='$window_name' first_window='$first_window' $LOG_E"
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

  # Get the active application running in the window
  local active_app=$(tmux display-message -t "$session_name:$window_name" -p '#{pane_current_command}')
  if [[ "$active_app" != "$TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION" ]]; then
    return 1
  fi

  echo "Recommending skipping send command | active_app='${active_app}' TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION='${TMUX_SESSION_WINDOW_SKIP_IF_APPLICATION}' $LOG_S"
  return 0
}

# Compiles an exported bash function into a single-line command string suitable for tmux
#
# This utility takes a function that has been exported (via export -f) and converts
# it into a command string that can be sent to a tmux session. The resulting string
# includes both the function definition and a call to execute it.
#
# Parameters:
#   $1 - function_name (required) - Name of the exported function to compile
#
# Returns:
#   A single-line command string containing the function definition and execution call
#
# Usage Pattern:
#   1. Define your function
#   2. Export it with 'export -f function_name' 
#   3. Compile it with this utility
#   4. Send via tmux_session_window::run_cmd
#
# Example:
#   function my_interactive_tool() {
#     echo "Running interactive tool..."
#     selected=$(find . -name "*.log" | fzf)
#     [ -n "$selected" ] && vim "$selected"
#   }
#   export -f my_interactive_tool
#   
#   cmd="$(tmux_session_window::cmd::from_exported_fxn 'my_interactive_tool')"
#   tmux_session_window::run_cmd "my-session" "tool-window" "$cmd"
#
# The compiled command will look like:
#   my_interactive_tool() { echo "Running..."; selected=$(find . -name "*.log" | fzf); [ -n "$selected" ] && vim "$selected"; }; my_interactive_tool
function tmux_session_window::cmd::from_exported_fxn() {
  local function_name="${1:?}"
  
  # Check if function exists and is exported
  if ! declare -f "$function_name" >/dev/null 2>&1; then
    echo "ERROR: Function '$function_name' does not exist, did you remember to export it?" >&2
    return 1
  fi
  
  # Get the function definition
  local function_def
  function_def=$(declare -f "$function_name" 2>/dev/null)
  
  if [[ -z "$function_def" ]]; then
    echo "ERROR: Function '$function_name' exists but could not be serialized, did you remember to export it?" >&2
    return 1
  fi
  
  echo "$function_def; $function_name" | tr -s '\n ' '; ' | sed -e 's/() ;{ ;/() {/'
}

# Tmux Session/Window/Command orchestration function
#
# Ensures a tmux session exists, ensures a window exists within that session,
# switches to that session:window, and sends a command to it.
#
# Parameters:
#   $1 - session_name (required) - Name of the tmux session
#   $2 - window_name  (optional) - Name of the window (defaults to "first-window")
#   $3 - command      (optional) - Command to send (defaults to "echo 'hello world'")
#
# Flow:
#   1. Create session if it doesn't exist (naming first window if created)
#   2. Switch to the session
#   3. Create window if it doesn't exist
#   4. Switch to the window
#   5. Send command to the session:window
#
# Example:
#   tmux_session_window::run_cmd "my-session" "build-window" "npm run build"
#   tmux_session_window::run_cmd "dev-session"  # uses defaults for window and command
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
