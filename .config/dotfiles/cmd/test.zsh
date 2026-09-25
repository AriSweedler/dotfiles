# dotfiles/cmd/test.zsh — `dotfiles test`: the hermetic suite, or one plugin suite.

help_test() {
  cat <<EOF
the hermetic suite, or one zsh plugin suite by name

${c_bold}Usage${c_rst}
  ${DF} test [NAME]

  Without NAME: every tests/test_*.sh under $(help::tilde "${ARI_DOTFILES_TESTS}"),
  each in a fake HOME with brew/launchctl/curl shims; nothing reaches this
  machine. With NAME (raycast, json_sort, …): the plugin suite
  ~/.config/zsh/plugins/NAME.test.zsh under its OTTO_TEST__ZSH_PLUGINS_<NAME>
  gate.

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_TESTS)
      the hermetic suite's directory
      (default $(help::tilde "${ARI_DOTFILES_TESTS}"))
  $(ENV ARI_DOTFILES_BLESS_GOLDEN)
      1 rewrites the report goldens from the renderer:
      ARI_DOTFILES_BLESS_GOLDEN=1 bash tests/test_report_render.sh
EOF
}

cmd_test() {
  (( $# <= 1 )) || usage_error "test takes at most one name | args='$*'"
  if (( $# == 0 )); then
    exec bash "${ARI_DOTFILES_TESTS}/run.sh"
  fi
  local name="${1%.test.zsh}" suite
  suite="${ARI_DOTFILES_CONFIG}/zsh/plugins/${name}.test.zsh"
  [[ -r "${suite}" ]] || usage_error "no such plugin suite | name='${name}' path='${suite}'"
  exec env "OTTO_TEST__ZSH_PLUGINS_${name:u}=true" zsh "${suite}"
}
