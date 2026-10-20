# dotfiles/cmd/apply.zsh — `dotfiles apply STEP..`: init for the named steps only.

help_apply() {
  cat <<EOF
init for the named steps only

${c_bold}Usage${c_rst}
  ${DF} apply STEP.. [--dry-run] [--json]
  ${DF} apply --edit [STEP..] [--dry-run]
  ${DF} apply --edit FILE [--dry-run]

  The same check → apply → re-check as init, for exactly the steps named. A
  step's needs are a gate, not an auto-include: name them too when they are not
  in place yet. 'dotfiles steps' lists the names.

  With --edit, every step opens in \$EDITOR as a plan,
  $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/apply-plan.dfapply, in run order:
  'apply|skip STEP  # description · group · needs · last result (age)',
  check-only when it has no apply. The steps named start as apply; with none
  named, those whose newest result failed or warned and that have an apply.
  On save every line is checked (an applied step's need that last failed must
  be applied too), confirmed on a terminal, and the 'apply' steps run as one
  apply. Unchanged, with no step named, applies nothing. A plan with bad lines
  is kept: edit it again, or resume it with --edit FILE.

${c_bold}Flags${c_rst}
  --dry-run   run every apply with each mutation logged instead of executed, so
              the plan printed is the real one
  --edit      choose the steps in \$EDITOR, every step listed; a FILE argument
              resumes a plan that did not pass
  --json      print summary.json instead of the table (stdout is data, stderr
              is logs); not with --edit

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STATE_DIR)
      where runs and summaries are written
      (default $(help::tilde "${ARI_DOTFILES_STATE_DIR}"))
  $(ENV ARI_DOTFILES_APPLY_TIMEOUT_SECS)
      seconds an apply may run before it is killed (default ${ARI_DOTFILES_APPLY_TIMEOUT_SECS})
EOF
}

# Flags may follow the step names (zparseopts would stop at the first name), so the line is
# sorted by hand: every -word is a flag, everything else a step (or, with --edit, the one plan
# file: a word with a / or ending .dfapply).
cmd_apply() {
  local -a steps=() arg
  local json=0 dry=0 edit=0
  for arg in "$@"; do
    case "${arg}" in
      --json) json=1 ;;
      --dry-run) dry=1 ;;
      --edit) edit=1 ;;
      -*) usage_error "apply: bad flag | flag='${arg}'" ;;
      *) steps+=("${arg}") ;;
    esac
  done
  (( dry )) && export ARI_DOTFILES_DRY_RUN=1
  if (( edit )); then
    (( ! json )) || usage_error "apply: --edit opens a plan in \$EDITOR, so --json does not apply"
    need_lib "${ARI_DOTFILES_CMD}/run/edit.zsh" || return 3
    if (( ${#steps} == 1 )) && [[ "${steps[1]}" == */* || "${steps[1]}" == *.dfapply ]]; then
      runplan::apply "${steps[1]}"
    else
      runplan::apply "" "${steps[@]}"
    fi
    return
  fi
  (( ${#steps} )) || usage_error "apply requires STEP.. | steps='${(j:,:)STEPS}'"
  run::main setup "${(j:,:)steps}" "" "${json}"
}
