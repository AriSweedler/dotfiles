# dotfiles/cmd/healthcheck.zsh — `dotfiles healthcheck`: every step's check, reported, nothing applied.
# `init` and `apply` are the same run with autofix; the three share run::run and run::main below.
# --edit (all three) is cmd/run/edit.zsh.

help_healthcheck() {
  cat <<EOF
every step's check, reported; nothing applied

${c_bold}Usage${c_rst}
  ${DF} healthcheck [--only STEP,..] [--group GROUP] [--dry-run] [--json]
  ${DF} healthcheck --edit [FILE] [--only STEP,..] [--group GROUP] [--dry-run]

  Runs each step's check in its own zsh under a watchdog and prints one line
  per step, then the roll-up. Exit 0 when every step is ok, warn or skip; 1
  when one failed; 2 when one could not be checked (a busy brew, a timeout, a
  crash). Nothing is changed, with or without --dry-run. Results land in
  $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/runs/<run id>/ and last-check.json;
  'dotfiles steps' lists the steps.

  With --edit (a terminal only), the checks run and print as above; then, when
  a step has something to apply, a plan opens in \$EDITOR,
  $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/healthcheck-plan.dfcheck: one
  'skip STEP  # reason: what the apply does' line per step, every one skip
  (the healthcheck applies nothing on its own), and the steps to fix by hand as
  comments. On save every line is checked; after a confirm, the 'apply' steps
  run in a fresh 'dotfiles apply'. A plan with bad lines is kept: edit it
  again, or resume it with --edit FILE, read against last-check.json.

${c_bold}Flags${c_rst}
  --only STEP,..   exactly these steps; a step's needs are a gate, not an
                   auto-include
  --group GROUP    one group: ${(j:, :)STEP_GROUPS}
  --dry-run        accepted; a healthcheck changes nothing either way (with
                   --edit, the apply it hands over to is a dry run)
  --edit [FILE]    after the checks, choose the steps to apply in \$EDITOR;
                   FILE resumes a plan without checking again
  --json           print summary.json instead of the table (stdout is data,
                   stderr is logs); not with --edit

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
  local -a only=() group=() json=() dry=() edit=()
  zparseopts -D -E -F -K -- -only:=only -group:=group -json=json -dry-run=dry -edit=edit || usage_error "healthcheck: bad flags | args='$*'"
  if (( ${#edit} )); then
    (( $# <= 1 )) || usage_error "healthcheck --edit takes at most one FILE | args='$*'"
    (( ! ${#json} )) || usage_error "healthcheck: --edit opens a plan in \$EDITOR, so --json does not apply"
    if (( $# )); then
      (( ${#only} + ${#group} == 0 )) || usage_error "healthcheck --edit FILE resumes a plan, so --only and --group do not apply"
    else
      [[ -t 0 && -t 1 ]] || usage_error "healthcheck --edit opens \$EDITOR: it needs a terminal | fix='${CLI_NAME} healthcheck, then ${CLI_NAME} apply STEP..'"
    fi
  else
    (( $# == 0 )) || usage_error "healthcheck takes no positional arguments | args='$*'"
  fi
  # A read-only run is its own dry run: the flag changes nothing here (with --edit, the apply it
  # hands over to is a dry run).
  local -i dry_apply=${#dry}
  is_dry_run && dry_apply=1
  export ARI_DOTFILES_DRY_RUN=0
  typeset -g RUN_VERB=healthcheck
  if (( ${#edit} )); then
    need_lib "${ARI_DOTFILES_CMD}/run/edit.zsh" || return 3
    runplan::healthcheck "${only[2]:-}" "${group[2]:-}" "${1:-}" "${dry_apply}"
    return
  fi
  run::main check "${only[2]:-}" "${group[2]:-}" "${#json}"
}

# run::run <check|setup> <only> <group> <json>: one run of a selection, summarized; the caller
# prints it and exits (run::end, or run::print_end then run::exit). A usage error must not take
# the lock or leave an empty run dir behind. The registry loads once per process, and a lock
# the caller already holds is kept (init --edit takes it before it removes its plan).
run::run() {
  local mode="${1}" only="${2}" group="${3}" json="${4}"
  (( ${#STEPS} )) || steps::load || exit 3
  local -a selected select_args=()
  [[ -z "${only}" ]] || select_args+=(--only "${only}")
  [[ -z "${group}" ]] || select_args+=(--group "${group}")
  steps::select "${select_args[@]}" || exit 64
  (( ${#selected} )) || usage_error "no step selected | only='${only}' group='${group}' steps='${(j:,:)STEPS}'"
  (( LOCK_HELD )) || lock::acquire "${mode}"
  RUN_JSON="${json}"
  run::begin "${mode}"
  steps::run_all
  run::summarize
}

# check | setup, for a selection: the run, printed, then the exit.
run::main() {
  run::run "$@"
  run::end "${4}"
}
