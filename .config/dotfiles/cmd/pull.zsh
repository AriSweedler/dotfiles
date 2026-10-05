# dotfiles/cmd/pull.zsh — `dotfiles pull`: bring the shared tier up to origin (fast-forward, or
# replay local commits on top), then init.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_pull() {
  cat <<EOF
update the shared tier from origin, replaying local commits on top, then 'dotfiles init'

${c_bold}Usage${c_rst}
  ${DF} pull [--dry-run]

  'git df pull --rebase --autostash': a fast-forward when nothing is local,
  otherwise the local commits are replayed onto origin, with uncommitted edits
  stashed around it. A replay that conflicts is aborted, the tier is left as it
  was, and the conflicting files are named: resolve by hand
  ('git df pull --rebase'), then pull again. Then init runs, so new steps,
  skills and jobs in the pulled commits take effect. The local tier is never
  pulled: it has one machine.

${c_bold}Flags${c_rst}
  --dry-run   print the pull and every init apply, change nothing

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_REMOTE)
      the shared repo (default ${ARI_DOTFILES_REMOTE})
EOF
}

# True (0) while a rebase is stopped in the shared tier.
is_rebase_in_progress() {
  local dir
  for dir in rebase-merge rebase-apply; do
    [[ -d "$(repo_git shared rev-parse --git-path "${dir}")" ]] && return 0
  done
  return 1
}

# The pull, and on a stopped replay: name the conflicts, abort (the autostash comes back with it).
pull_rebase() {
  run_mut repo_git shared pull --rebase --autostash && return 0
  if ! is_rebase_in_progress; then
    log::err "pull failed before replaying anything | fix='git df pull --rebase' see='the git output above'"
    return 1
  fi
  local -a conflicts=("${(@f)$(repo_git shared diff --name-only --diff-filter=U 2>/dev/null)}")
  repo_git shared rebase --abort
  log::err "local commits conflict with origin; pull aborted, nothing changed | conflicts='${(j:, :)conflicts:#}' fix='git df pull --rebase, resolve, git df rebase --continue, then dotfiles pull'"
  return 1
}

cmd_pull() {
  [[ "${1:-}" != --dry-run ]] || { export ARI_DOTFILES_DRY_RUN=1; shift; }
  (( $# == 0 )) || usage_error "pull takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}"
  check_prerequisites git || return 1
  slow=5 step pull pull_rebase || return 1   # a fetch takes seconds; that is not slow
  log::info "pulled | took='$(elapsed "${start}")s'"
  cmd_init   # ends the process with the run's exit code
}
