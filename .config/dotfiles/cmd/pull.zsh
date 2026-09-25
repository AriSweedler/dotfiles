# dotfiles/cmd/pull.zsh — `dotfiles pull`: fast-forward the shared tier, then init.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_pull() {
  cat <<EOF
dotfiles pull [--dry-run]   fast-forward the shared tier from origin, then 'dotfiles init'

  A pull that is not a fast-forward is refused: commit or push what is here first.
EOF
}

cmd_pull() {
  [[ "${1:-}" != --dry-run ]] || { export DOTFILES_DRY_RUN=1; shift; }
  (( $# == 0 )) || usage_error "pull takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}"
  check_prerequisites git || return 1
  slow=5 step pull run_mut repo_git shared pull --ff-only || return 1   # a fetch takes seconds; that is not slow
  cmd_init || return 1
  log::info "pull done | took='$(elapsed "${start}")s'"
}
