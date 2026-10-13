# dotfiles/cmd/verify.zsh — `dotfiles verify`: the weekly job. A healthcheck of every step with
# one retry of the errors, then the report on the Desktop (rewritten only when the set of
# problems changes) and a banner. The report logic is cmd/verify/report.zsh, loaded on demand.

help_verify() {
  cat <<EOF
the weekly check: healthcheck, retry, Desktop report, banner

${c_bold}Usage${c_rst}
  ${DF} verify [--force-report] [--no-notify] [--json]

  What the dotfiles-verify job plugin runs on Monday. Every step is checked;
  steps that errored are retried once after ${ARI_DOTFILES_RETRY_SECS}s; the result is compared
  with the last one and at most one report is written to $(help::tilde "${ARI_DOTFILES_DESKTOP_DIR}")
  (deleting it = acknowledged; a passing run archives it).
  Trail: $(help::tilde "${VERIFY_TRAIL}")
  Log:   $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/verify/log.txt

${c_bold}Flags${c_rst}
  --force-report   write the report even when the set of problems is unchanged
  --no-notify      no banner (an interactive run never banners; the job does)
  --json           print summary.json instead of the table
  --show           print the current report (Desktop, else newest archived); runs nothing

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STATE_DIR)
      where runs, the trail and the report archive live
      (default $(help::tilde "${ARI_DOTFILES_STATE_DIR}"))
  $(ENV ARI_DOTFILES_DESKTOP_DIR)
      where the report is written (default $(help::tilde "${ARI_DOTFILES_DESKTOP_DIR}"))
  $(ENV ARI_DOTFILES_RETRY_SECS)
      pause before the one retry of errored steps; 0 disables it
      (default ${ARI_DOTFILES_RETRY_SECS})
  $(ENV ARI_DOTFILES_INVOKED_BY)
      set by the job plugin; with it, banners go through terminal-notifier
      instead of the log
  $(ENV ARI_DOTFILES_NO_NOTIFY)
      1 = never banner, whatever set ARI_DOTFILES_INVOKED_BY
EOF
}

cmd_verify() {
  local -a force=() quiet=() json=() show=()
  zparseopts -D -F -K -- -force-report=force -no-notify=quiet -json=json -show=show || usage_error "verify: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "verify takes no positional arguments | args='$*'"
  if (( ${#show} )); then
    (( ${#force} + ${#json} == 0 )) || usage_error "verify: --show runs nothing, so --force-report and --json do not apply"
    verify::show
    return
  fi
  (( ${#quiet} )) && export ARI_DOTFILES_NO_NOTIFY=1
  steps::load || exit 3
  need_lib "${ARI_DOTFILES_CMD}/verify/report.zsh"
  lock::acquire verify
  mkdir -p "${ARI_DOTFILES_STATE_DIR}"
  local LOG_DIR="${ARI_DOTFILES_STATE_DIR}"
  log_init verify 8
  log::redirect_all_output_to_logfile "${LOG_FILE}"
  local -a selected=("${STEPS[@]}")
  export ARI_DOTFILES_DRY_RUN=0
  run::begin check
  log::info "verify | run_id='${RUN_ID}' invoked_by='${ARI_DOTFILES_INVOKED_BY:-interactive}'"
  steps::run_all
  steps::retry_errored "${ARI_DOTFILES_RETRY_SECS}"
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

# --show: the report a human would open, read-only. No lock, run dir, log, banner or state write;
# it must not reach the cmd_verify path above. The archived note goes to stderr so stdout stays
# the report itself (`--show > x.md` is the file).
verify::show() {
  if [[ -f "${REPORT_PATH}" ]]; then
    ui::markdown "${REPORT_PATH}"
    return
  fi
  local newest
  newest="$(verify::_newest_archive)"
  if [[ -n "${newest}" ]]; then
    zmodload -F zsh/stat b:zstat 2>/dev/null || true
    local when
    when="$(zstat -F '%Y-%m-%d %H:%M' +mtime -- "${newest}" 2>/dev/null || true)"
    ui::paint grey "archived report from ${when:-an unknown date}, no current one on the Desktop: $(ui::paths "${newest}")" >&2
    ui::markdown "${newest}"
    return
  fi
  print -r -- "no verify report$(verify::_last_run)"
}

# The newest *.md under the reports archive by mtime, or nothing.
verify::_newest_archive() {
  local -a found=("${ARI_DOTFILES_STATE_DIR}"/reports/*.md(N.om))
  (( ${#found} )) && print -r -- "${found[1]}"
  return 0
}

# "; last verify <when>: <status>" from last_result.json, else the trail's last status line, else "".
verify::_last_run() {
  setopt localoptions extendedglob
  local when="" st=""
  if [[ -r "${LAST_RESULT_FILE}" ]]; then
    when="$(jq -r '.ts // ""' "${LAST_RESULT_FILE}" 2>/dev/null || true)"
    st="$(jq -r '.status // ""' "${LAST_RESULT_FILE}" 2>/dev/null || true)"
  fi
  if [[ -z "${when}" && -r "${VERIFY_TRAIL}" ]]; then
    local line
    line="$(grep -F "[verify] status='" "${VERIFY_TRAIL}" 2>/dev/null | tail -n 1 || true)"
    if [[ "${line}" == (#b)([0-9-]##\ [0-9:]##)\ \[verify\]\ status=\'([^\']#)\'* ]]; then
      when="${match[1]}" st="${match[2]}"
    fi
  fi
  [[ -n "${when}" ]] || return 0
  print -r -- "; last verify ${when}: ${st:-unknown}"
}
