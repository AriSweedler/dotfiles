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

function tmux::_slice_history() {
  local from="${1:-1}"  # 1-indexed inclusive start
  local to="${2:-$from}"  # 1-indexed inclusive end
  local prompt_re="${3:-❮|❯}"
  local extra_lines=$(($(tmux::_prompt_line_count) - 1))

  # After tac, structure is: output, prompt, [extra lines], blank, (repeat)
  # Print all commands whose prompt_count falls within [from, to] inclusive
  local output
  output=$(cat | awk -v re="$prompt_re" -v from="$from" -v to="$to" -v skip_count="$extra_lines" '
    $0 ~ re {
      in_range = (prompt_count >= from - 1 && prompt_count < to)
      prompt_count++
      if (in_range) {
        print  # Print the prompt line with command
      }
      for (i = 0; i < skip_count; i++) {
        getline  # Read and skip extra prompt lines
      }
      next
    }
    prompt_count >= from - 1 && prompt_count < to {
      print  # Print the output lines
    }
  ')

  if [ -z "$output" ]; then
    log::warn "No command found in history range ${from}..${to}"
    return 1
  fi

  print -r -- "$output"
}

function tmux::_debug_pbpaste() {
  local d="${c_grey}${(l:$COLUMNS::-:)}${c_rst}"
  printf "%b\n%s\n%b" "${d}" "$(pbpaste)" "${d}"
}

function tmux::cap() {
  [ -z "$TMUX" ] && return

  local prompt_re="${TMUX_PROMPT_RE:-❮|❯}"
  local from to less_mode=false

  # Parse arguments:
  #   tcap        → most recent 1 command        (slice 1..1)
  #   tcap 3      → most recent 3 commands        (slice 1..3)
  #   tcap -2     → just the 2nd most recent       (slice 2..2)
  #   tcap 1 3    → commands 1 through 3           (slice 1..3)
  #   tcap -l ... → open result in less (can combine with above)
  local -a args=()
  local past_opts=false
  for arg in "$@"; do
    if ! $past_opts && [[ "$arg" == "--" ]]; then
      past_opts=true; continue
    fi
    if ! $past_opts && [[ "$arg" == "-l" ]]; then
      less_mode=true
    else
      args+=("$arg")
    fi
  done

  case ${#args[@]} in
    0) from=1; to=1 ;;
    1)
      local n="${args[1]}"
      if (( n < 0 )); then
        from=$(( -n )); to=$from
      else
        from=1; to=$n
      fi
      ;;
    2) from="${args[1]}"; to="${args[2]}" ;;
    *) log::err "Usage: tcap [N | -N | FROM TO] [-l]"; return 1 ;;
  esac

  # Swap if reversed (e.g. tcap 3 1 → tcap 1 3)
  if (( from > to )); then
    local tmp=$from; from=$to; to=$tmp
  fi

  # +1 offset to skip the tcap command itself in the scrollback
  local slice_from=$((from + 1))
  local slice_to=$((to + 1))

  tmux capture-pane -p -S - \
    | tac \
    | tmux::_slice_history "$slice_from" "$slice_to" "$prompt_re" \
    | tac \
    | pbcopy

  local label
  if (( from == to )); then
    label="command ${from}"
  else
    label="commands ${from}..${to}"
  fi
  log::info "Copied ${label} to clipboard"
  tmux::_debug_pbpaste

  if $less_mode; then
    log::info "Opening clipboard in less"
    local tmp_file=$(mktemp)
    TRAPEXIT() {
      rm -f -- "${tmp_file:?locally scoped variables do not penetrate into TRAPEXIT scope}"
    }
    pbpaste > "${tmp_file}"
    less "${tmp_file}"
  fi
}

alias tmv='tmux::rename-window'
alias tclear='tmux::clear'
alias tcap='tmux::cap'
alias tcap_all='tmux::cap_all'
