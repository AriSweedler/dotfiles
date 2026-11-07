function zvm_config() {
  ZVM_LINE_INIT_MODE="$ZVM_MODE_INSERT"
  ZVM_VI_INSERT_ESCAPE_BINDKEY="jk"
  ZVM_SYSTEM_CLIPBOARD_ENABLED="true"
  ZVM_CLIPBOARD_COPY_CMD=pbcopy
  ZVM_CLIPBOARD_PASTE_CMD=pbpaste
  ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BEAM
  ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
}

function zvm_after_init() {
  fzf::init

  function delete-entire-line {
    zle beginning-of-line
    zle kill-line
  }
  zle -N delete-entire-line
  bindkey -M vicmd 'D' delete-entire-line

  # TODO: Can we configure changing the cursor when we enter 'menu select' mode?
}

# The shared flake places it (home.nix); Homebrew's copy is the fallback on a machine not on
# Nix yet.
() {
  local f
  for f in "${XDG_DATA_HOME:-${HOME}/.local/share}/zsh-vi-mode" /opt/homebrew/opt/zsh-vi-mode/share/zsh-vi-mode; do
    [[ -r "${f}/zsh-vi-mode.plugin.zsh" ]] && { source "${f}/zsh-vi-mode.plugin.zsh"; return; }
  done
}
