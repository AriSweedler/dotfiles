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

function tmux::cap() {
  local file="${TMUX_CAPTURE_FILE:-"$HOME/Desktop/capture.txt"}"

  log::info "Capturing scrollback buffer to file | file_var='TMUX_CAPTURE_FILE' file='${c_grey}${file}${c_rst}'"
  tmux capture-pane -p -S - > "${file}"
}

function tmux::cap_one() {
  [ -z "$TMUX" ] && return

  # Match your prompt line via an awk regex (❯)
  local prompt_re="${TMUX_PROMPT_RE:-❮|❯}"

  # Pipeline: Reverse text, capture from (first regex match (inclusive) to next
  # (exclusive), un-reverse text, place on clipboard
  #
  # Result: Copy text from second-to-last prompt (inclusive) to last prompt
  # (exclusive)
  #
  # NOTE: My PS1 is 2 lines, so I use '1,2' as the range in the 'sed d' command.
  tmux capture-pane -p -S - \
    | tac \
    | awk -v re="$prompt_re" '
      (!s && $0 ~ re && (s=NR)), (s && $0 ~ re && NR!=s)
    ' \
    | sed '1,2d' \
    | tac \
    | pbcopy
  log::info "Copied previous command + output to clipboard | prompt_re_var='TMUX_PROMPT_RE' prompt_re='${prompt_re}'"
}
