# dotfiles/cmd/verify.zsh — `dotfiles verify`: the weekly job. A healthcheck of every step with
# one retry of the errors, then the report on the Desktop (rewritten only when the set of
# problems changes) and a banner. The report logic is cmd/verify/report.zsh, loaded on demand.

help_verify() {
  cat <<EOF
dotfiles verify [--force-report] [--no-notify] [--json]   the weekly check: healthcheck + one retry + report + banner

  What the dotfiles-verify job plugin runs on Monday. Every step is checked; steps that errored
  are retried once after ${NEW_MACHINE_RETRY_SECS}s; the result is compared with the last one and at
  most one report is written to ${NEW_MACHINE_DESKTOP_DIR} (deleting it = acknowledged).
  Trail: ${VERIFY_TRAIL}. Log: ${NEW_MACHINE_STATE_DIR}/verify/log.txt.

  --force-report   write the report even when the problems are unchanged
  --no-notify      no banner (interactive runs never banner; NEW_MACHINE_INVOKED_BY marks launchd)
  --json           print summary.json instead of the table
EOF
}

cmd_verify() {
  local -a force=() quiet=() json=()
  zparseopts -D -F -K -- -force-report=force -no-notify=quiet -json=json || usage_error "verify: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "verify takes no positional arguments | args='$*'"
  (( ${#quiet} )) && export DOTFILES_NO_NOTIFY=1
  steps::load || exit 3
  need_lib "${DOTFILES_CMD}/verify/report.zsh"
  lock::acquire verify
  mkdir -p "${NEW_MACHINE_STATE_DIR}"
  local LOG_DIR="${NEW_MACHINE_STATE_DIR}"
  log_init verify 8
  log::redirect_all_output_to_logfile "${LOG_FILE}"
  local -a selected=("${STEPS[@]}")
  export DOTFILES_DRY_RUN=0
  run::begin check
  log::info "verify | run_id='${RUN_ID}' invoked_by='${NEW_MACHINE_INVOKED_BY:-interactive}'"
  steps::run_all
  steps::retry_errored "${NEW_MACHINE_RETRY_SECS}"
  run::summarize
  verify::decide_and_notify "${#force}"
  run::end "${#json}"
}

# report::decide is pure and returns the whole plan, hud text included; report::write applies it
# and prints the plan extended with {report: written|unchanged|archived|left_edited|none}.
verify::decide_and_notify() {
  local force_report="${1}"
  local summary="${RUN_DIR}/summary.json" decision="${RUN_DIR}/decision.json" applied="${RUN_DIR}/decision.applied.json"
  local -a decide_args=()
  if (( force_report )); then
    decide_args+=(--force-report)
  fi
  report::decide "${summary}" "${decide_args[@]}" > "${decision}"
  report::write "${summary}" "${LOG_FILE}" "${decision}" > "${applied}"
  local message seconds open_url
  message="$(jq -r '.hud.message // ""' "${decision}")"
  seconds="$(jq -r '.hud.seconds // 0' "${decision}")"
  open_url="$(jq -r '.hud.open // ""' "${decision}")"
  if [[ -n "${message}" ]]; then
    hud "${message}" "${seconds}" "${open_url}"
  fi
  note "status='$(jq -r '.status' "${summary}")' fingerprint='$(jq -r '.fingerprint // ""' "${decision}")' report='$(jq -r '.report // "none"' "${applied}")' undeclared='$(jq -r '.undeclared_count // 0' "${decision}")'"
}
