# dotfiles/cmd/apply.zsh — `dotfiles apply STEP..`: setup for the named steps only.

help_apply() {
  cat <<EOF
setup for the named steps only

${c_bold}Usage${c_rst}
  ${DF} apply STEP.. [--dry-run] [--json]

  The same check → apply → re-check as setup, for exactly the steps named. A
  step's needs are a gate, not an auto-include: name them too when they are not
  in place yet. 'dotfiles steps' lists the names.

${c_bold}Flags${c_rst}
  --dry-run   run every apply with each mutation logged instead of executed, so
              the plan printed is the real one
  --json      print summary.json instead of the table (stdout is data, stderr
              is logs)

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STATE_DIR)
      where runs and summaries are written
      (default $(help::tilde "${ARI_DOTFILES_STATE_DIR}"))
  $(ENV ARI_DOTFILES_APPLY_TIMEOUT_SECS)
      seconds an apply may run before it is killed (default ${ARI_DOTFILES_APPLY_TIMEOUT_SECS})
EOF
}

# Flags may follow the step names (zparseopts would stop at the first name), so the line is
# sorted by hand: every -word is a flag, everything else a step.
cmd_apply() {
  local -a steps=() arg
  local json=0 dry=0
  for arg in "$@"; do
    case "${arg}" in
      --json) json=1 ;;
      --dry-run) dry=1 ;;
      -*) usage_error "apply: bad flag | flag='${arg}'" ;;
      *) steps+=("${arg}") ;;
    esac
  done
  (( ${#steps} )) || usage_error "apply requires STEP.. | steps='${(j:,:)STEPS}'"
  (( dry )) && export ARI_DOTFILES_DRY_RUN=1
  run::main setup "${(j:,:)steps}" "" "${json}"
}
