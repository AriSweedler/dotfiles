# Change the install location of tpm. Keep these in sync with
# ~/.config/tmux/plugin/tpm.conf
export TMUX_DATA_DIR="$XDG_DATA_HOME/tmux"
export TMUX_PLUGIN_MANAGER_ROOT="$TMUX_DATA_DIR/tpm"
export TMUX_PLUGIN_MANAGER_PATH="$TMUX_DATA_DIR/tpm_plugins"

function ensure_tpm_installed() {
  [ -d "$TMUX_PLUGIN_MANAGER_ROOT" ] && return

  function install_tpm() {
    log::info "Installing the Tmux Plugin Manager (tpm) | TMUX_PLUGIN_MANAGER_ROOT='$TMUX_PLUGIN_MANAGER_ROOT'"
    git clone https://github.com/tmux-plugins/tpm "$TMUX_PLUGIN_MANAGER_ROOT"
  }
  if ! install_tpm; then
    log::err "Failed to install tpm"
  fi
  unset -f install_tpm

  # Install tpm plugins
  if ! "${TMUX_PLUGIN_MANAGER_ROOT}/bindings/install_plugins"; then
    log::err "Failed to install tpm plugins. Try 'Prefix' + 'Capital I'"
    return 1
  fi
}
ensure_tpm_installed
unset -f ensure_tpm_installed

function tmux::rename-window() {
  [ -z "$TMUX" ] && return
  tmux rename-window "$@"
}

function tmux::clear() {
  clear
  tmux clear-history
  log::info "Cleared scrollback buffer"
}

function tmux::cap_all() {
  local arg="${1:-capture.txt}"
  local capture_dir="${TMUX_CAPTURE_DIR:-$HOME/Desktop}"

  if [[ "$arg" == "-" ]]; then
    tmux capture-pane -p -S - | pbcopy
    log::info "Captured scrollback buffer to clipboard"
  else
    # Use absolute path as-is, otherwise put in capture_dir
    local dest
    [[ "$arg" == /* ]] && dest="$arg" || dest="${capture_dir}/${arg}"
    tmux capture-pane -p -S - > "${dest}"
    log::info "Captured scrollback buffer to file | file='${c_grey}${dest}${c_rst}'"
  fi
}

function tmux::_visual_width() {
  local str="$1"
  local len=${#str}
  local extra=0
  # Add +1 for each wide character (emoji in U+1F300+ range)
  for (( i=1; i<=len; i++ )); do
    local c="${str[$i]}"
    local codepoint=$(printf '%d' "'$c")
    # Emoji ranges: U+1F300-U+1FAFF (127744-129535) and others
    (( codepoint >= 127744 )) && ((extra++))
  done
  echo $((len + extra))
}

function tmux::_prompt_line_count() {
  local expanded total=0
  expanded=$(print -P "$PS1")

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip ANSI escape codes to get visual width
    # Handles SGR (colors), cursor movement, and other CSI sequences
    local stripped=$(printf '%s' "$line" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g')
    local visual_width=$(tmux::_visual_width "$stripped")
    # Ceiling division: (x-1)/n+1, with special case for empty lines
    local wrapped=$(( visual_width ? (visual_width - 1) / COLUMNS + 1 : 1 ))
    total=$((total + wrapped))
  done <<< "$expanded"

  echo "$total"
}

function tmux::_skip_history_entries() {
  local history_num="${1:-1}"  # 1-indexed: 1=most recent, 2=2nd most recent, etc.
  local prompt_re="${2:-❮|❯}"
  local extra_lines=$(($(tmux::_prompt_line_count) - 1))

  # After tac, structure is: output, prompt, [extra lines], blank, (repeat)
  # To get command N, print the prompt line and output, skip extra prompt lines
  local output
  output=$(cat | awk -v re="$prompt_re" -v target="$history_num" -v skip_count="$extra_lines" '
    $0 ~ re {
      in_range = (prompt_count >= target - 1 && prompt_count < target)
      prompt_count++
      if (in_range) {
        print  # Print the prompt line with command
      }
      for (i = 0; i < skip_count; i++) {
        getline  # Read and skip additional lines before prompt_re
      }
      next     # Skip processing for extra lines
    }
    prompt_count >= target - 1 && prompt_count < target {
      print  # Print the output lines
    }
  ')

  if [ -z "$output" ]; then
    log::warn "No command found at history position ${history_num}"
    return 1
  fi

  echo "$output"
}

function tmux::_debug_pbpaste() {
  local d="${c_grey}${(l:$COLUMNS::-:)}${c_rst}"
  printf "%b\n%s\n%b" "${d}" "$(pbpaste)" "${d}"
}

function tmux::cap_one() {
  [ -z "$TMUX" ] && return

  # Parse arguments: accept a number for how many commands back (1=most recent completed)
  # Add 1 to skip the tcap command itself in the history
  local commands_back="${1:-1}"
  local history_num=$((commands_back + 1))

  # Match your prompt line via an awk regex
  local prompt_re="${TMUX_PROMPT_RE:-❮|❯}"

  # Pipeline: Reverse text, extract the Nth most recent command output
  # (excluding prompt), un-reverse text, copy to clipboard
  tmux capture-pane -p -S - \
    | tac \
    | tmux::_skip_history_entries "$history_num" "$prompt_re" \
    | tac \
    | pbcopy
  log::info "Copied command + output to clipboard | commands_back='${commands_back}' prompt_re_var='TMUX_PROMPT_RE' prompt_re='${prompt_re}'"
  tmux::_debug_pbpaste

  if [ "${1:-}" = '-l' ]; then
    log::info "Opening clipboard in less"
    tmp_file=$(mktemp)
    TRAPEXIT() {
      rm -f -- "${tmp_file:?locally scoped variables do not penetrate into TRAPEXIT scope}"
    }
    run_cmd pbpaste > "${tmp_file}"
    run_cmd less "${tmp_file}"
  fi
}

alias tmv='tmux::rename-window'
alias tclear='tmux::clear'
alias tcap='tmux::cap_one'
alias tcap_all='tmux::cap_all'
