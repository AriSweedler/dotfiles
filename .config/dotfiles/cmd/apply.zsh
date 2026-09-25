# dotfiles/cmd/apply.zsh — `dotfiles apply STEP..`: setup for the named steps only.

help_apply() {
  cat <<EOF
dotfiles apply STEP.. [--dry-run] [--json]   setup for the named steps only

  The same check → apply → re-check as setup, for exactly the steps named (their needs are a
  gate, not an auto-include). 'dotfiles steps' lists the names.
EOF
}

cmd_apply() {
  local -a json=() dry=()
  zparseopts -D -F -K -- -json=json -dry-run=dry || usage_error "apply: bad flags | args='$*'"
  (( $# > 0 )) || usage_error "apply requires STEP.. | steps='${(j:,:)STEPS}'"
  (( ${#dry} )) && export DOTFILES_DRY_RUN=1
  run::main setup "${(j:,:)@}" "" "${#json}"
}
