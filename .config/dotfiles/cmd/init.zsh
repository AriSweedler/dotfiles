# dotfiles/cmd/init.zsh — `dotfiles init`: converge the machine. Every step checks, applies only
# where it finds drift (a changed Brewfile, Raycast behind), re-checks; then status. What
# bootstrap ends in and pull runs after its fetch.

help_init() {
  cat <<EOF
converge this machine: check every step, apply where one drifted, then status

${c_bold}Usage${c_rst}
  ${DF} init [--only STEP,..] [--group GROUP] [--dry-run] [--json]

  The healthcheck, then for every step that failed and has an apply, the apply
  and a second check; a step still failing afterwards is reported as
  apply_did_not_converge. A converged machine changes nothing, so a changed
  Brewfile installs its new items, Raycast syncs when it is behind, and the
  rest is a check. When the brew step fails, the later groups are skipped:
  their tools come from it. Ends with 'dotfiles status'.

  What the bootstrap one-liner ends in and 'dotfiles pull' runs after its
  fetch. 'dotfiles apply STEP' is 'init --only STEP'; 'dotfiles steps' lists
  the steps and their groups.

${c_bold}Flags${c_rst}
  --only STEP,..   exactly these steps; a step's needs are a gate, not an
                   auto-include
  --group GROUP    one group: ${(j:, :)STEP_GROUPS}
  --dry-run        run every apply with each mutation logged instead of
                   executed, so the plan printed is the real one (also accepted
                   before the verb)
  --json           print summary.json instead of the table and status (stdout
                   is data, stderr is logs)

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
  local -a only=() group=() json=() dry=()
  zparseopts -D -F -K -- -only:=only -group:=group -json=json -dry-run=dry || usage_error "init: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "init takes no positional arguments | args='$*'"
  (( ${#dry} )) && export ARI_DOTFILES_DRY_RUN=1
  if (( ${#json} )); then run::main setup "${only[2]:-}" "${group[2]:-}" 1; fi
  # The human run: run::main's table, then status before the exit. The exit stays explicit
  # (run::exit): zsh skips the EXIT trap when ERR_EXIT ends the shell, which would leak the lock.
  steps::load || exit 3
  local -a selected select_args=()
  [[ -z "${only[2]:-}" ]] || select_args+=(--only "${only[2]}")
  [[ -z "${group[2]:-}" ]] || select_args+=(--group "${group[2]}")
  steps::select "${select_args[@]}" || exit 64
  (( ${#selected} )) || usage_error "no step selected | only='${only[2]:-}' group='${group[2]:-}' steps='${(j:,:)STEPS}'"
  lock::acquire setup
  run::begin setup
  steps::run_all
  run::summarize
  run::print_human
  run::print_manual
  print
  cmd_status
  run::exit
}
