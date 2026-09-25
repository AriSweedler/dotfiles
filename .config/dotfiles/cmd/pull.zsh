# dotfiles/cmd/pull.zsh — `dotfiles pull`: fast-forward the shared tier, then init.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_pull() {
  cat <<EOF
fast-forward the shared tier from origin, then 'dotfiles init'

${c_bold}Usage${c_rst}
  ${DF} pull [--dry-run]

  A pull that is not a fast-forward is refused: commit or push what is here
  first. Then init runs, so new steps, skills and jobs in the pulled commits
  take effect.

${c_bold}Flags${c_rst}
  --dry-run   print the pull and every init apply, change nothing

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_REMOTE)
      the shared repo (default ${ARI_DOTFILES_REMOTE})
EOF
}

cmd_pull() {
  [[ "${1:-}" != --dry-run ]] || { export ARI_DOTFILES_DRY_RUN=1; shift; }
  (( $# == 0 )) || usage_error "pull takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}"
  check_prerequisites git || return 1
  slow=5 step pull run_mut repo_git shared pull --ff-only || return 1   # a fetch takes seconds; that is not slow
  log::info "pulled | took='$(elapsed "${start}")s'"
  cmd_init   # ends the process with the run's exit code
}
