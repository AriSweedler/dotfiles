# dotfiles/cmd/steps.zsh — `dotfiles steps`: the registry, in run order.

help_steps() {
  cat <<EOF
dotfiles steps   list every step: name, group, needs, tools, apply, description

  One file each under ${DOTFILES_STEPS}; adding a file adds a step. Order is by group
  (${(j:, :)STEP_GROUPS}), then by --needs, then by name.
EOF
}

cmd_steps() {
  (( $# == 0 )) || usage_error "steps takes no arguments | args='$*'"
  steps::load || exit 3
  steps::list
}
