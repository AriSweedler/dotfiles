alias vi='nvim'
alias vim='nvim'
alias vimdiff='nvim -d'

prepend_to_path "$XDG_DATA_HOME/bob/nvim-bin"

# The :Dotfiles command is defined in nvim's plugin/snacks.lua (same picker as <C-T>d).
function vi_::dotfiles() {
  ( cd "${HOME}" && "${EDITOR}" +Dotfiles )
}
alias vi_dotfiles=vi_::dotfiles
