# dotfiles/cmd/test.zsh — `dotfiles test`: the hermetic suite, or one plugin suite.

help_test() {
  cat <<EOF
dotfiles test [NAME]   run the hermetic suite (bash tests/run.sh), or one zsh plugin suite by name

  Without NAME: every tests/test_*.sh under ${DOTFILES_TESTS}, each in a fake HOME with
  brew/launchctl/curl shims; nothing reaches this machine. With NAME (raycast, json_sort, …):
  ~/.config/zsh/plugins/NAME.test.zsh under its OTTO_TEST__ZSH_PLUGINS_<NAME> gate.
EOF
}

cmd_test() {
  (( $# <= 1 )) || usage_error "test takes at most one name | args='$*'"
  if (( $# == 0 )); then
    exec bash "${DOTFILES_TESTS}/run.sh"
  fi
  local name="${1%.test.zsh}" suite
  suite="${DOTFILES_CONFIG}/zsh/plugins/${name}.test.zsh"
  [[ -r "${suite}" ]] || usage_error "no such plugin suite | name='${name}' path='${suite}'"
  exec env "OTTO_TEST__ZSH_PLUGINS_${name:u}=true" zsh "${suite}"
}
