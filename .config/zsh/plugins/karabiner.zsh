# The clone, not ~/.config/karabiner: under Nix that is a tree of per-file links, and a file
# created there would land outside the repo.
KARABINER_HOME="${HOME}/dotfiles/.config/karabiner"

function vi_::karabiner_home() {
  cd "${KARABINER_HOME}"
  "${EDITOR}" "${KARABINER_HOME}"
}
alias vi_kh=vi_::karabiner_home

function vi_::karabiner_index() {
  cd "${KARABINER_HOME}"
  "${EDITOR}" "${KARABINER_HOME}/karabiner.ts/src/index.ts"
}
alias vi_ki=vi_::karabiner_index
