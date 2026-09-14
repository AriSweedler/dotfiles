KARABINER_HOME="${XDG_CONFIG_HOME}/karabiner"

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
