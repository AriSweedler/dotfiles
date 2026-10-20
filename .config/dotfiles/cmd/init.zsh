# dotfiles/cmd/init.zsh — `dotfiles init`: converge the machine. Every step checks, applies only
# where it finds drift (a changed Brewfile, Raycast behind), re-checks; then status. What
# bootstrap ends in.

help_init() {
  cat <<EOF
converge this machine: check every step, apply where one drifted, then status

${c_bold}Usage${c_rst}
  ${DF} init [--only STEP,..] [--group GROUP] [--dry-run] [--json]
  ${DF} init --edit [FILE] [--only STEP,..] [--group GROUP] [--dry-run]

  The healthcheck, then for every step that failed and has an apply, the apply
  and a second check; a step still failing afterwards is reported as
  apply_did_not_converge. A converged machine changes nothing, so a changed
  Brewfile installs its new items, Raycast syncs when it is behind, and the
  rest is a check. When the brew step fails, the later groups are skipped:
  their tools come from it. Ends with 'dotfiles status'.

  With --edit, the checks run first, side by side as the healthcheck runs them,
  and print; then a plan opens in \$EDITOR,
  $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/init-plan.dfinit: one
  'apply STEP  # reason: what the apply does' line per step with something to
  apply, the steps to fix by hand as comments, the rest for reference. On save
  every line is checked; then exactly the 'apply' steps run as init runs them,
  and status. An unchanged plan runs as written; nothing to apply opens no
  editor. A plan with bad lines is kept: edit it again, or resume it with
  --edit FILE, read against last-check.json.

  What the bootstrap one-liner ends in. 'dotfiles apply STEP' is
  'init --only STEP'; 'dotfiles steps' lists the steps and their groups.

${c_bold}Flags${c_rst}
  --only STEP,..   exactly these steps; a step's needs are a gate, not an
                   auto-include
  --group GROUP    one group: ${(j:, :)STEP_GROUPS}
  --dry-run        run every apply with each mutation logged instead of
                   executed, so the plan printed is the real one (also accepted
                   before the verb)
  --edit [FILE]    check, then choose the steps to apply in \$EDITOR; FILE
                   resumes a plan without checking again
  --json           print summary.json instead of the table and status (stdout
                   is data, stderr is logs); not with --edit

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STATE_DIR)
      where runs and summaries are written
      (default $(help::tilde "${ARI_DOTFILES_STATE_DIR}"))
  $(ENV ARI_DOTFILES_REMOTE)
      the shared repo the dotfiles_repo step clones
      (default ${ARI_DOTFILES_REMOTE})
  $(ENV ARI_DOTFILES_PUSH_URL)
      the push url dotfiles_repo gives a clone fetching over something else,
      so 'git df push' goes over ssh; empty = none
      (default ${ARI_DOTFILES_PUSH_URL})
  $(ENV ARI_DOTFILES_SSH_KEY_OP_ITEM)
      1Password item holding the ssh key's "Absolute path" and "password"
      fields; unset = no key to load (the local tier sets it)
  $(ENV ARI_DOTFILES_SSH_KEY_OP_VAULT)
      that item's vault (the local tier sets it)
  $(ENV ARI_DOTFILES_SSH_KEY_PATH)
      the key file; the check reads the agent for it, so no 1Password call
      (the local tier sets it)
  $(ENV ARI_DOTFILES_CHECK_TIMEOUT_SECS)
      seconds a check may run (default ${ARI_DOTFILES_CHECK_TIMEOUT_SECS})
  $(ENV ARI_DOTFILES_APPLY_TIMEOUT_SECS)
      seconds an apply may run (default ${ARI_DOTFILES_APPLY_TIMEOUT_SECS})
  $(ENV ARI_DOTFILES_BREW_PREFIXES)
      where brew and other tools are probed when not on PATH
      (default '${ARI_DOTFILES_BREW_PREFIXES}')
EOF
}

cmd_init() {
  local -a only=() group=() json=() dry=() edit=()
  zparseopts -D -E -F -K -- -only:=only -group:=group -json=json -dry-run=dry -edit=edit || usage_error "init: bad flags | args='$*'"
  if (( ${#edit} )); then
    (( $# <= 1 )) || usage_error "init --edit takes at most one FILE | args='$*'"
    (( ! ${#json} )) || usage_error "init: --edit opens a plan in \$EDITOR, so --json does not apply"
    (( ! $# || ${#only} + ${#group} == 0 )) || usage_error "init --edit FILE resumes a plan, so --only and --group do not apply"
  else
    (( $# == 0 )) || usage_error "init takes no positional arguments | args='$*'"
  fi
  (( ${#dry} )) && export ARI_DOTFILES_DRY_RUN=1
  typeset -g RUN_VERB=init
  if (( ${#edit} )); then
    need_lib "${ARI_DOTFILES_CMD}/run/edit.zsh" || return 3
    runplan::init "${only[2]:-}" "${group[2]:-}" "${1:-}"
  fi
  if (( ${#json} )); then run::main setup "${only[2]:-}" "${group[2]:-}" 1; fi
  # The human run: run::run's table, then status before the exit. The exit stays explicit
  # (run::exit): zsh skips the EXIT trap when ERR_EXIT ends the shell, which would leak the lock.
  run::run setup "${only[2]:-}" "${group[2]:-}" 0
  run::print_end 0
  print
  cmd_status
  run::exit
}
