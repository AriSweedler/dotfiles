# Ensure tpm is installed
tpm="$HOME/.tmux/plugins/tpm"
if ! [ -d "$tpm" ]; then
  if ! git clone https://github.com/tmux-plugins/tpm "$tpm"; then
    log::err "Failed to install tpm"
  fi
fi
unset tpm
