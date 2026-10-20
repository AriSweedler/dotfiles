# dotfiles/cmd/apply.zsh — `dotfiles apply STEP..`: init for the named steps only.

verb::define apply 'init for the named steps only'
verb::usage apply 'apply STEP.. [--dry-run] [--json]'
verb::about apply <<'EOF'
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
EOF
verb::edit apply apply::edit '[STEP..|FILE] [--dry-run]' \
  'choose the steps in \$EDITOR, every step listed; a FILE argument resumes a plan that did not pass'
verb::flag apply '--dry-run' 'run every apply with each mutation logged instead of executed, so the plan printed is the real one'
verb::flag apply '--json' 'print summary.json instead of the table (stdout is data, stderr is logs); not with --edit'
verb::env apply ARI_DOTFILES_STATE_DIR 'where runs and summaries are written' '$(help::tilde "${ARI_DOTFILES_STATE_DIR}")'
verb::env apply ARI_DOTFILES_APPLY_TIMEOUT_SECS 'seconds an apply may run before it is killed' '${ARI_DOTFILES_APPLY_TIMEOUT_SECS}'

# Flags may follow the step names: verb::parse takes them anywhere, and every other word is a step.
cmd_apply() {
  local -A opts; local -a args
  verb::parse apply "$@"
  (( ${+opts[--edit]} )) && { apply::edit "${@:#--edit}"; return; }
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  (( ${#args} )) || usage_error "apply requires STEP.. | steps='${(j:,:)STEPS}'"
  run::main setup "${(j:,:)args}" "" "${+opts[--json]}"
}

# apply --edit [STEP..] | FILE: cmd/run/edit.zsh's plan of every step. The one plan file is a word
# with a / or ending .dfapply; any other word is a step.
apply::edit() {
  local -A opts; local -a args
  verb::parse apply "$@"
  (( ! ${+opts[--json]} )) || usage_error "apply: --edit opens a plan in \$EDITOR, so --json does not apply"
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  need_lib "${ARI_DOTFILES_CMD}/run/edit.zsh" || return 3
  if (( ${#args} == 1 )) && [[ "${args[1]}" == */* || "${args[1]}" == *.dfapply ]]; then
    runplan::apply "${args[1]}"
  else
    runplan::apply "" "${args[@]}"
  fi
}
