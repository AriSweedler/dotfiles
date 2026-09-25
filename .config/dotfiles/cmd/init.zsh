# dotfiles/cmd/init.zsh — `dotfiles init`: setup's repo group, then status. The dotfiles
# themselves converged, on a machine that may have nothing else yet; what pull runs after its fetch.

help_init() {
  cat <<EOF
setup's repo group, then status

${c_bold}Usage${c_rst}
  ${DF} init [--dry-run]

  'dotfiles setup --group repo' followed by 'dotfiles status'. The repo group
  is the dotfiles themselves: the shared bare repo cloned, tracking origin,
  checked out into HOME with its hooks and submodules (dotfiles_repo); the
  local bare repo with its allowlist and hooks (local_dotfiles_repo); the
  skills linked (claude_skills); the GitHub ssh key in the agent, its
  passphrase from 1Password (ssh_key); the jobs launchd job (dotfiles_jobs).
  Every step is idempotent. What 'dotfiles pull' runs after its fetch; the
  bootstrap one-liner runs the full setup instead.

${c_bold}Flags${c_rst}
  --dry-run   run every apply with each mutation logged instead of executed

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_REMOTE)
      the shared repo to clone when missing
      (default ${ARI_DOTFILES_REMOTE})
  $(ENV ARI_DOTFILES_PUSH_URL)
      the push url a clone fetching over something else gets, so 'git df
      push' goes over ssh while the clone needed no key; empty = none
      (default ${ARI_DOTFILES_PUSH_URL})
  $(ENV ARI_DOTFILES_SSH_KEY_OP_ITEM)
      1Password item holding the ssh key's "Absolute path" and "password"
      fields; unset = no key to load (the local tier sets it)
  $(ENV ARI_DOTFILES_SSH_KEY_OP_VAULT)
      that item's vault (the local tier sets it)
  $(ENV ARI_DOTFILES_SSH_KEY_PATH)
      the key file; the check reads the agent for it, so no 1Password call
      (the local tier sets it)
EOF
}

# run::main's setup, with status between the table and the exit. The exit stays explicit (run::exit):
# zsh skips the EXIT trap when ERR_EXIT ends the shell, which would leak the lock.
cmd_init() {
  local -a dry=()
  zparseopts -D -F -K -- -dry-run=dry || usage_error "init: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "init takes no arguments | args='$*'"
  (( ${#dry} )) && export ARI_DOTFILES_DRY_RUN=1
  steps::load || exit 3
  local -a selected
  steps::select --group repo || exit 64
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
