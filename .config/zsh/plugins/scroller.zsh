# ANSI Scroll Region Library
# Provides functions to run commands in contained scrolling areas

# Setup a scroll region with optional top and bottom line numbers
setup_scroll_region() {
  local top=${1:-5}
  local bottom=${2:-25}

  # Save cursor, clear screen, set scroll region
  printf '\033[?1049h\033[2J\033[%d;%dr\033[%d;1H' "$top" "$bottom" "$top"
}

# Cleanup and restore normal terminal state
cleanup_scroll_region() {
  # Reset scroll region, restore screen
  printf '\033[r\033[?1049l'
}

# Run a command in a scroll region with header and footer, includes logging like run_cmd
run_scroll() {
  local start_time end_time duration
  local exit_code=0
  local current_row bottom_row

  # Create temporary file for output capture
  local tmp_output="/tmp/run_scroll_$(date +%s)_$$.log"
  cat << EOF > "${tmp_output}"
Running command with output in a scrollable terminal window

$(set -- $(printf "'%s' " "$@"); echo "$*")
--------------------------------------------------------------------------------
EOF

  # Log the command (like run_cmd does)
  local tmp_output_log="${c_grey}${tmp_output}${c_rst}"
  "log::${lvl}" "$@ | output='${tmp_output_log}'"

  start_time=$(date +%s.%N)

  # Don't save cursor, don't query position - just use where we are now
  local scroll_size=${SCROLL_REGION_SIZE:-10}

  # Create N empty lines below current cursor position
  for (( i=0; i<scroll_size; i++ )); do
    printf '\n'
  done

  # Move cursor back up to where we started and set scroll region
  printf '\033[%dA' "$scroll_size"  # Move cursor up N lines

  # Get current position for scroll region setup
  printf '\033[6n'
  read -s -d R pos 2>/dev/null || pos="10;1"
  current_row=${pos##*\[}
  current_row=${current_row%;*}

  if [[ ! "$current_row" =~ ^[0-9]+$ ]]; then
    current_row=10
  fi

  local end_row=$((current_row + scroll_size - 1))

  # Set scroll region and position cursor at start
  printf '\033[%d;%dr\033[%d;1H' "$current_row" "$end_row" "$current_row"

  # Run command, tee output to temp file, and capture exit code
  "$@" 2>&1 | tee -a "$tmp_output"
  exit_code=${PIPESTATUS[0]}

  end_time=$(date +%s.%N)
  duration=$(printf "%.2f" $(echo "$end_time - $start_time" | bc))

  # Reset scroll region and clear the temporary lines
  printf '\033[r'

  # Move back to start of scroll region and clear all the lines we used
  printf '\033[%d;1H' "$current_row"
  for (( i=0; i<scroll_size; i++ )); do
    printf '\033[2K'  # Clear entire line
    if (( i < scroll_size - 1 )); then
      printf '\n'  # Move to next line (except for last iteration)
    fi
  done

  # Position cursor at start of scroll region for next output
  printf '\033[%d;1H' "$current_row"

  # Print timing info after cleanup
  if (( exit_code == 0 )); then
    log::info "Command completed | duration='${duration}s' output_file='$tmp_output_log'"
  else
    log::err "Command failed | exit_code='$exit_code' duration='${duration}s' output_file='$tmp_output_log'"
  fi

  # Log failure like run_cmd does
  if (( exit_code != 0 )); then
    set -- $(printf "'%s' " "$@")
    "log::${lvl_fail}" "cmd failed | rc=$exit_code cmd_quoted=|$*|"
  fi

  return $exit_code
}

# Simple scroll region without header/footer - just constrain output to middle of screen
run_simple_scroll() {
  local cmd="$*"
  local exit_code=0

  # Set scroll region (lines 5-20) without alternate screen
  printf '\033[5;20r\033[5;1H'

  # Run command
  eval "$cmd"
  exit_code=$?

  # Reset scroll region
  printf '\033[r'

  return $exit_code
}

# Run command with custom scroll region dimensions
run_custom_scroll() {
  local top="$1"
  local bottom="$2"
  shift 2
  local cmd="$*"
  local exit_code=0

  # Setup custom scroll region
  printf '\033[?1049h\033[2J'
  printf '\033[%d;%dr\033[%d;1H' "$top" "$bottom" "$top"

  # Run command
  eval "$cmd"
  exit_code=$?

  # Cleanup
  printf '\033[r\033[?1049l'

  return $exit_code
}
