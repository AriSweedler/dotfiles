# dotfiles/cmd/healthcheck.zsh — `dotfiles healthcheck`: every step's check, reported, nothing applied.
# `setup` and `apply` are the same run with autofix; the three share run::main below.

help_healthcheck() {
  cat <<EOF
every step's check, reported; nothing applied

${c_bold}Usage${c_rst}
  ${DF} healthcheck [--only STEP,..] [--group GROUP] [--json]

  Runs each step's check in its own zsh under a watchdog and prints one line
  per step, then the roll-up. Exit 0 when every step is ok, warn or skip; 1
  when one failed; 2 when one could not be checked (a busy brew, a timeout, a
  crash). Nothing is changed, with or without --dry-run. Results land in
  $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/runs/<run id>/ and last-check.json;
  'dotfiles steps' lists the steps.

${c_bold}Flags${c_rst}
  --only STEP,..   exactly these steps; a step's needs are a gate, not an
                   auto-include
  --group GROUP    one group: ${(j:, :)STEP_GROUPS}
  --json           print summary.json instead of the table (stdout is data,
                   stderr is logs)

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STATE_DIR)
      where runs and summaries are written
      (default $(help::tilde "${ARI_DOTFILES_STATE_DIR}"))
  $(ENV ARI_DOTFILES_CHECK_TIMEOUT_SECS)
      seconds a check may run before it is killed and reported as error
      timed_out (default ${ARI_DOTFILES_CHECK_TIMEOUT_SECS})
  $(ENV ARI_DOTFILES_LOCK_MAX_AGE_SECS)
      a live lock older than this is taken over (default ${ARI_DOTFILES_LOCK_MAX_AGE_SECS})
  $(ENV ARI_DOTFILES_BREW_PREFIXES)
      where brew and other tools are probed when not on PATH, as under launchd
      (default '${ARI_DOTFILES_BREW_PREFIXES}')
EOF
}

cmd_healthcheck() {
  local -a only=() group=() json=() dry=()
  zparseopts -D -F -K -- -only:=only -group:=group -json=json -dry-run=dry || usage_error "healthcheck: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "healthcheck takes no positional arguments | args='$*'"
  # A read-only run is its own dry run: the flag changes nothing here.
  export ARI_DOTFILES_DRY_RUN=0
  run::main check "${only[2]:-}" "${group[2]:-}" "${#json}"
}

# check | setup, for a selection. A usage error must not take the lock or leave an empty run dir behind.
run::main() {
  local mode="${1}" only="${2}" group="${3}" json="${4}"
  steps::load || exit 3
  local -a selected select_args=()
  [[ -z "${only}" ]] || select_args+=(--only "${only}")
  [[ -z "${group}" ]] || select_args+=(--group "${group}")
  steps::select "${select_args[@]}" || exit 64
  (( ${#selected} )) || usage_error "no step selected | only='${only}' group='${group}' steps='${(j:,:)STEPS}'"
  lock::acquire "${mode}"
  run::begin "${mode}"
  steps::run_all
  run::summarize
  run::end "${json}"
}
