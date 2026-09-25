# dotfiles/cmd/steps.zsh — `dotfiles steps`: the registry, in run order.

help_steps() {
  cat <<EOF
every step in run order, with its group, needs, tools and apply

${c_bold}Usage${c_rst}
  ${DF} steps

  A step is one file under $(help::tilde "${ARI_DOTFILES_STEPS}") that declares itself,
    step::declare NAME --group G [--needs a,b] [--tools t] --desc D
  and defines check::NAME and, when it can fix what it finds, apply::NAME.
  Adding the file adds the step. Run order: the groups in order
  (${(j:, :)STEP_GROUPS}); inside a group, a step runs after the steps its
  --needs names (each must have ended ok or warn, or the step is skipped);
  ties by name. 'tools' names binaries the runner probes before the check.

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STEPS)
      the steps directory (default $(help::tilde "${ARI_DOTFILES_STEPS}"))
EOF
}

cmd_steps() {
  (( $# == 0 )) || usage_error "steps takes no arguments | args='$*'"
  steps::load || exit 3
  steps::list
}
