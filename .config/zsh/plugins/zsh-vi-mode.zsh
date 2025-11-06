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

  # TODO: Can we configure changing the cursor when we enter 'menu select' mode?

  function delete-entire-line {
    zle beginning-of-line
    zle kill-line
  }
  zle -N delete-entire-line
  bindkey -M vicmd 'D' delete-entire-line

  # TODO: Can we configure changing the cursor when we enter 'menu select' mode?
}

source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
