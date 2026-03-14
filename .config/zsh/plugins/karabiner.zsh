KARABINER_HOME="${XDG_CONFIG_HOME}/karabiner"

function v::karabiner_home() {
  cd "${KARABINER_HOME}"
  "${EDITOR}" "${KARABINER_HOME}"
}
alias vi_kh=v::vkarabiner_home

function v::vkarabiner_index() {
  cd "${KARABINER_HOME}"
  "${EDITOR}" "${KARABINER_HOME}/karabiner.ts/src/index.ts"
}
alias vi_ki=v::vkarabiner_index
