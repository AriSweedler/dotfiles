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
