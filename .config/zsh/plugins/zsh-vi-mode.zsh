source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
function zvm_config() {
  ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT

  ZVM_VI_INSERT_ESCAPE_BINDKEY=jk

  zle -N delete-entire-line
  function delete-entire-line {
    zle beginning-of-line
    zle kill-line
  }
  bindkey -M vicmd 'D' delete-entire-line
}
zvm_config

zvm_after_init_commands+=('fzf::init')
