# dotfiles/cmd/help.zsh — `dotfiles help [VERB]`: the top-level help, or one verb's.

help_help() {
  cat <<EOF
the verbs, or one verb's help

${c_bold}Usage${c_rst}
  ${DF} help
  ${DF} help VERB

  Without VERB, the same as 'dotfiles --help' (and a bare 'dotfiles'): every
  verb with its one-line description. With VERB, the same as
  'dotfiles VERB --help'. Any sub-verb answers --help with its verb's help,
  e.g. 'dotfiles jobs list --help'.
EOF
}

cmd_help() {
  (( $# <= 1 )) || usage_error "help takes at most one verb | args='$*'"
  if (( $# == 0 )); then help; return 0; fi
  local verb="${1:l}"
  (( ${+functions[cmd_${verb}]} )) || usage_error "Unknown verb | verb='${verb}' valid='${(j:, :)${(f)$(verbs)}}'"
  help_verb "${verb}"
}
