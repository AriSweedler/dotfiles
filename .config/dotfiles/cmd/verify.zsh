# dotfiles/cmd/verify.zsh — `dotfiles verify`: the weekly job. A healthcheck of every step with
# one retry of the errors, then the report on the Desktop (rewritten only when the set of
# problems changes) and a banner. The report logic is cmd/verify/report.zsh, loaded on demand.

verb::define verify 'the weekly check: healthcheck, retry, Desktop report, banner'
verb::usage verify 'verify [--force-report] [--no-notify] [--json]' 'verify --show'
verb::about verify <<'EOF'
What the dotfiles-verify job plugin runs on Monday. Every step is checked;
steps that errored are retried once after ${ARI_DOTFILES_RETRY_SECS}s; the result is compared
with the last one and at most one report is written to $(help::tilde "${ARI_DOTFILES_DESKTOP_DIR}")
(deleting it = acknowledged; a passing run archives it).
Trail: $(help::tilde "${VERIFY_TRAIL}")
Log:   $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/verify/log.txt
EOF
verb::edit verify verify::edit_cmd '' \
  'open the Desktop report (else the newest *.edited*.md) in \$EDITOR for notes; runs nothing, commits nothing. Keep line 1: without that marker verify treats the file as foreign. Then prints the next step'
verb::flag verify '--force-report' 'write the report even when the set of problems is unchanged'
verb::flag verify '--no-notify' 'no banner (an interactive run never banners; the job does)'
verb::flag verify '--json' 'print summary.json instead of the table'
verb::flag verify '--show' 'print the current report (Desktop, else newest archived); runs nothing'
verb::env verify ARI_DOTFILES_STATE_DIR 'where runs, the trail and the report archive live' '$(help::tilde "${ARI_DOTFILES_STATE_DIR}")'
verb::env verify ARI_DOTFILES_DESKTOP_DIR 'where the report is written' '$(help::tilde "${ARI_DOTFILES_DESKTOP_DIR}")'
verb::env verify ARI_DOTFILES_RETRY_SECS 'pause before the one retry of errored steps; 0 disables it' '${ARI_DOTFILES_RETRY_SECS}'
verb::env verify ARI_DOTFILES_INVOKED_BY 'set by the job plugin; with it, banners go through terminal-notifier instead of the log'
verb::env verify ARI_DOTFILES_NO_NOTIFY '1 = never banner, whatever set ARI_DOTFILES_INVOKED_BY'

cmd_verify() {
  local -A opts; local -a args
  verb::parse verify "$@"
  (( ${#args} == 0 )) || usage_error "verify takes no positional arguments | args='${args[*]}'"
  (( ${+opts[--edit]} )) && { verify::edit_cmd "${@:#--edit}"; return; }
  if (( ${+opts[--show]} )); then
    (( ${+opts[--force-report]} + ${+opts[--json]} == 0 )) || usage_error "verify: --show runs nothing, so --force-report and --json do not apply"
    verify::show
    return
  fi
  (( ${+opts[--no-notify]} )) && export ARI_DOTFILES_NO_NOTIFY=1
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
  verify::decide_and_notify "${+opts[--force-report]}"
  run::end "${+opts[--json]}"
}

# report::decide is pure and returns the whole plan, hud text included; report::write applies it
# and prints the plan extended with {report: written|unchanged|archived|left_edited|none}.
verify::decide_and_notify() {
  local force_report="${1}"
  local summary="${RUN_DIR}/summary.json" decision="${RUN_DIR}/decision.json" applied="${RUN_DIR}/decision.applied.json"
  report::decide "${summary}" "${force_report}" > "${decision}"
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

# --edit: the report a human annotates, opened in $EDITOR. Like --show it takes no lock and writes
# no state; the only write is the editor's. An edited report is one verify never overwrites or
# archives (its sha no longer matches), but only while line 1 is still our marker: without it the
# file is foreign and left on the Desktop for good, so a lost marker is caught here.
verify::edit_cmd() {
  local -A opts; local -a args
  verb::parse verify "$@"
  (( ${#args} == 0 )) || usage_error "verify takes no positional arguments | args='${args[*]}'"
  (( ${+opts[--force-report]} + ${+opts[--json]} + ${+opts[--show]} == 0 )) || usage_error "verify: --edit runs nothing, so --force-report, --json and --show do not apply"
  need_lib "${ARI_DOTFILES_CMD}/verify/report.zsh"
  local file
  file="$(verify::_editable_report)"
  if [[ -z "${file}" ]]; then
    print -r -- "no verify report to edit$(verify::_last_run)"
    return 0
  fi
  local first="" rc=0
  first="$(head -n 1 -- "${file}")"
  typeset -g VERIFY_EDIT_MARKER=""
  report::is_marker "${first}" && VERIFY_EDIT_MARKER="${first}"
  edit::session "${file}" --check verify::_marker_check --what "the report" --resume "${CLI_NAME} verify --edit" || rc=$?
  case "${rc}" in
    2) print -r -- "verify: no change | file=$(ui::paths "${file}")" ;;
    0) print -r -- "verify: notes saved | file=$(ui::paths "${file}")"
       [[ -z "${VERIFY_EDIT_SAID:-}" ]] || print -r -- "${VERIFY_EDIT_SAID}" ;;
    *) return 1 ;;
  esac
  local feed
  feed="$(grep -m 1 -E '^[[:space:]]*claude "' -- "${file}" 2>/dev/null || true)"
  if [[ -n "${feed}" ]]; then
    print -r -- "next: in a terminal, cd ~ and paste:"
    print -r -- "  ${feed##[[:space:]]#}"
  else
    print -r -- "next: ${CLI_NAME} verify --force-report"
  fi
}

# verify::_marker_check FILE: edit::session's check. A report that had the marker keeps it; on a
# terminal a lost one is put back or given up (VERIFY_EDIT_SAID says which), else it fails.
verify::_marker_check() {
  local file="${1}" marker="${VERIFY_EDIT_MARKER}" first=""
  typeset -g VERIFY_EDIT_SAID=""
  first="$(head -n 1 -- "${file}")"
  [[ -z "${marker}" ]] || report::is_marker "${first}" && return 0
  log::warn "line 1 is no longer the report marker: verify now treats this file as foreign and never moves it | file='${file}'"
  if [[ -t 0 && -t 1 ]]; then
    if ui::confirm "Restore the marker as line 1?"; then
      verify::_restore_marker "${file}" "${marker}" || return 1
      VERIFY_EDIT_SAID="verify: marker restored | file=$(ui::paths "${file}")"
    else
      VERIFY_EDIT_SAID="verify: left without its marker; it is yours now | file=$(ui::paths "${file}")"
    fi
    return 0
  fi
  log::err "marker lost; put it back as line 1 | marker='${marker}'"
  return 1
}

# The report --edit opens: of the canonical Desktop report and the one the last run wrote (a
# collision name, when a foreign file holds the canonical one), the first that is ours, else the
# first that exists; else the newest report a run moved aside as edited.
verify::_editable_report() {
  local -a candidates=("${REPORT_PATH}"(N.))
  local last="" f first
  if [[ -r "${LAST_RESULT_FILE}" ]]; then
    last="$(jq -r '.report_path // ""' "${LAST_RESULT_FILE}" 2>/dev/null || true)"
    if [[ -n "${last}" && "${last}" != "${REPORT_PATH}" && -f "${last}" && "${last:h}" == "${ARI_DOTFILES_DESKTOP_DIR}" ]]; then candidates+=("${last}"); fi
  fi
  for f in "${candidates[@]}"; do
    first=""; IFS= read -r first < "${f}" || true
    if report::is_marker "${first}"; then print -r -- "${f}"; return 0; fi
  done
  if (( ${#candidates} )); then print -r -- "${candidates[1]}"; return 0; fi
  local -a edited=("${ARI_DOTFILES_DESKTOP_DIR}"/*.edited*.md(N.om))
  (( ${#edited} )) && print -r -- "${edited[1]}"
  return 0
}

# Puts MARKER back as line 1: in place of a line 1 that was the marker mangled, else above it.
verify::_restore_marker() {
  local file="${1}" marker="${2}" tmp
  local -a lines=("${(@f)$(<"${file}")}")
  if [[ "${lines[1]}" == '<!-- new-machine-report'* ]]; then lines[1]="${marker}"; else lines=("${marker}" "${lines[@]}"); fi
  tmp="${file}.edit.$$"
  print -rl -- "${lines[@]}" > "${tmp}" && mv -f -- "${tmp}" "${file}" || { rm -f -- "${tmp}"; log::err "could not restore the marker | file='${file}'"; return 1; }
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
