# Ensure tpm is installed
export TPM_ROOT="$XDG_DATA_HOME/tmux/tpm"
function ensure_tpm_installed() {
  [ -d "$TPM_ROOT" ] && return

  function install_tpm() {
    log::info "Installing the Tmux Plugin Manager (tpm) | TPM_ROOT='$TPM_ROOT'"
    git clone https://github.com/tmux-plugins/tpm "$TPM_ROOT"
  }
  if ! install_tpm; then
    log::err "Failed to install tpm"
  fi
  unset -f install_tpm
}
ensure_tpm_installed
unset -f ensure_tpm_installed
