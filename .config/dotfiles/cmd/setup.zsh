# dotfiles/cmd/setup.zsh — `dotfiles setup`: healthcheck with autofix. Bootstrap ends in it.

help_setup() {
  cat <<EOF
check every step, apply where a step can fix itself, re-check

${c_bold}Usage${c_rst}
  ${DF} setup [--only STEP,..] [--group GROUP] [--dry-run] [--json]

  The healthcheck, then for every step that failed and has an apply, the apply
  and a second check; a step still failing afterwards is reported as
  apply_did_not_converge. When the brew step fails, the later groups are
  skipped: their tools come from it. What the bootstrap one-liner ends in;
  'dotfiles apply STEP' is 'setup --only STEP', 'dotfiles init' is
  'setup --group repo'.

${c_bold}Flags${c_rst}
  --only STEP,..   exactly these steps; a step's needs are a gate, not an
                   auto-include
  --group GROUP    one group: ${(j:, :)STEP_GROUPS}
  --dry-run        run every apply with each mutation logged instead of
                   executed, so the plan printed is the real one (also accepted
                   before the verb)
  --json           print summary.json instead of the table (stdout is data,
                   stderr is logs)

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
  $(ENV ARI_DOTFILES_CHECK_TIMEOUT_SECS)
      seconds a check may run (default ${ARI_DOTFILES_CHECK_TIMEOUT_SECS})
  $(ENV ARI_DOTFILES_APPLY_TIMEOUT_SECS)
      seconds an apply may run (default ${ARI_DOTFILES_APPLY_TIMEOUT_SECS})
  $(ENV ARI_DOTFILES_BREW_PREFIXES)
      where brew and other tools are probed when not on PATH
      (default '${ARI_DOTFILES_BREW_PREFIXES}')
EOF
}

cmd_setup() {
  local -a only=() group=() json=() dry=()
  zparseopts -D -F -K -- -only:=only -group:=group -json=json -dry-run=dry || usage_error "setup: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "setup takes no positional arguments | args='$*'"
  (( ${#dry} )) && export ARI_DOTFILES_DRY_RUN=1
  run::main setup "${only[2]:-}" "${group[2]:-}" "${#json}"
}
