# dotfiles/lib/steps.zsh — steps as data, one runner.
#
# A step is one file, steps/<name>.zsh, that declares itself and defines its functions:
#
#   step::declare <name> [--group repo|brew|tools] [--needs a,b] [--tools t,u] [--desc D] [--abort]
#   check::<name>   pure: writes only under RUN_DIR, prints exactly one verdict line on stdout,
#                   logs on stderr, returns 0
#   apply::<name>   optional; mutates only through run_mut; returns the command's rc
#
# Adding a file registers the step. steps::load sources the directory, refuses a registry that
# does not add up (steps::validate), and computes the run order (steps::order): the groups in
# STEP_GROUPS order, and inside a group by --needs, ties by name. Each check and apply runs in a
# fresh zsh that sources this kernel and the step's own file, under a watchdog, so a crash never
# aborts the loop and only exported environment reaches a step.
zmodload zsh/datetime

typeset -ga STEPS=() STEPS_DECLARED=()
typeset -gA STEP_GROUP=() STEP_NEEDS=() STEP_TOOLS=() STEP_DESC=() STEP_FILE=()
typeset -ga STEP_GROUPS=(repo brew tools)   # run order of the groups
typeset -g STEP_ABORT_ON=""                  # in setup, a fail or error here skips every later step

# --- Registry ---

step::declare() {
  local name="${1:?step::declare needs a name}"; shift
  local group=tools needs="" tools="" desc="" abort=0
  while (( $# )); do case "${1}" in
    --group) group="${2}"; shift 2 ;;
    --needs) needs="${2}"; shift 2 ;;
    --tools) tools="${2}"; shift 2 ;;
    --desc)  desc="${2}"; shift 2 ;;
    --abort) abort=1; shift ;;
    *) print -u2 "[ERROR] step::declare: bad flag | step='${name}' flag='${1}'"; return 64 ;;
  esac; done
  (( ${STEPS_DECLARED[(Ie)${name}]} )) || STEPS_DECLARED+=("${name}")
  STEP_GROUP[${name}]="${group}"; STEP_NEEDS[${name}]="${needs}"; STEP_TOOLS[${name}]="${tools}"; STEP_DESC[${name}]="${desc}"
  STEP_FILE[${name}]="${${funcfiletrace[1]%:*}:t:r}"   # the file that declared it
  (( abort )) && STEP_ABORT_ON="${name}"
  return 0
}

# Source every step file, then validate and order. Exit 3 on a registry that does not add up.
steps::load() {
  local dir="${1:-${ARI_DOTFILES_STEPS}}" file
  for file in "${dir}"/*.zsh(N); do source "${file}" || return 3; done
  steps::validate || return 3
  steps::order
}

# Every declaration has a check and lives in the file of its name; every check has a declaration;
# groups are known; needs are known and in the same or an earlier group.
steps::validate() {
  local name need fn rc=0
  for name in "${STEPS_DECLARED[@]}"; do
    if (( ! ${+functions[check::${name}]} )); then print -u2 "[ERROR] step has no check | step='${name}' want='check::${name}'"; rc=3; fi
    if [[ "${STEP_FILE[${name}]}" != "${name}" ]]; then print -u2 "[ERROR] step declared in another file | step='${name}' file='${STEP_FILE[${name}]}.zsh'"; rc=3; fi
    if (( ! ${STEP_GROUPS[(Ie)${STEP_GROUP[${name}]}]} )); then print -u2 "[ERROR] unknown step group | step='${name}' group='${STEP_GROUP[${name}]}' known='${(j:,:)STEP_GROUPS}'"; rc=3; fi
    for need in ${(s:,:)STEP_NEEDS[${name}]}; do
      if (( ! ${STEPS_DECLARED[(Ie)${need}]} )); then print -u2 "[ERROR] step needs an unknown step | step='${name}' needs='${need}'"; rc=3; continue; fi
      if (( ${STEP_GROUPS[(Ie)${STEP_GROUP[${need}]}]} > ${STEP_GROUPS[(Ie)${STEP_GROUP[${name}]}]} )); then
        print -u2 "[ERROR] step needs a step from a later group | step='${name}' needs='${need}' groups='${(j:,:)STEP_GROUPS}'"; rc=3
      fi
    done
  done
  for fn in ${(k)functions[(I)check::*]}; do
    name="${fn#check::}"
    (( ${STEPS_DECLARED[(Ie)${name}]} )) || { print -u2 "[ERROR] check without a declaration | step='${name}' want='step::declare ${name}'"; rc=3; }
  done
  return "${rc}"
}

# True (0) when every need of a step is already in STEPS.
steps::is_ready() {
  local need
  for need in ${(s:,:)STEP_NEEDS[${1}]}; do (( ${STEPS[(Ie)${need}]} )) || return 1; done
  return 0
}

# Fills STEPS: group by group, and inside a group the first (by name) step whose needs are placed,
# until none is left. A cycle leaves steps unplaceable, which is an error.
steps::order() {
  STEPS=()
  local group name picked
  local -a pending
  for group in "${STEP_GROUPS[@]}"; do
    pending=(${(o)${(k)STEP_GROUP[(R)${group}]}})
    while (( ${#pending} )); do
      picked=""
      for name in "${pending[@]}"; do
        if steps::is_ready "${name}"; then picked="${name}"; break; fi
      done
      if [[ -z "${picked}" ]]; then print -u2 "[ERROR] step needs form a cycle | steps='${(j:,:)pending}'"; return 3; fi
      STEPS+=("${picked}")
      pending=("${(@)pending:#${picked}}")
    done
  done
}

step::is_known() { (( ${STEPS[(Ie)${1}]} )); }
# A step with an apply:: can fix what its check finds.
step::is_fixable() { (( ${+functions[apply::${1}]} )); }

# steps::select [--only a,b] [--group G]: fills the caller's `selected`, in STEPS order. --only names
# exactly the steps to run (needs are a gate, not an auto-include). Returns 64 on an unknown name.
steps::select() {
  local only="" group="" name
  while (( $# )); do case "${1}" in
    --only)   only="${2:-}"; shift 2 ;;
    --only=*) only="${1#--only=}"; shift ;;
    --group)  group="${2:-}"; shift 2 ;;
    *) log::err "steps::select: bad flag | flag='${1}'"; return 64 ;;
  esac; done
  selected=("${STEPS[@]}")
  if [[ -n "${group}" ]]; then
    local -a in_group=()
    for name in "${selected[@]}"; do [[ "${STEP_GROUP[${name}]}" == "${group}" ]] && in_group+=("${name}"); done
    selected=("${in_group[@]}")
  fi
  if [[ -n "${only}" ]]; then
    local -a wanted=(${(s:,:)only})
    for name in "${wanted[@]}"; do
      step::is_known "${name}" || { log::err "unknown step | step='${name}' known='${(j:,:)STEPS}'"; return 64; }
    done
    selected=("${(@)selected:*wanted}")
  fi
}

# name · group · needs · tools · apply · description, one line per step.
steps::list() {
  local name has_apply
  for name in "${STEPS[@]}"; do
    has_apply=no; step::is_fixable "${name}" && has_apply=yes
    printf '%-22s %-6s %-14s %-6s %-5s %s\n' "${name}" "${STEP_GROUP[${name}]}" "${STEP_NEEDS[${name}]:--}" "${STEP_TOOLS[${name}]:--}" "${has_apply}" "${STEP_DESC[${name}]}"
  done
}

# --- Running one step ---

step::result_status() {
  local file="${RUN_DIR}/${1}.result.json"
  if [[ -f "${file}" ]]; then
    jq -r '.status' "${file}"
  fi
}

# Runs one check::/apply:: in a fresh zsh that sources the kernel and the step's file, under the
# watchdog. The function name travels in $STEP so no shell quoting of the name is needed; colours
# are off there so the step logs stay plain.
step::run_isolated() {
  local kind="${1}" name="${2}" timeout_secs="${3}"
  export STEP="${name}"
  with_timeout "${timeout_secs}" env NO_COLOR=1 zsh -c '
    set -euo pipefail
    for f in "${ARI_DOTFILES_LIB}"/*.zsh(N); do source "${f}"; done
    source "${ARI_DOTFILES_STEPS}/${STEP}.zsh"
    "'"${kind}"'::${STEP}"'
}

# Runs the check, normalizing crashes and timeouts into error verdicts in <check_file>.
step::run_check() {
  local name="${1}" check_file="${2}" log_file="${3}"
  local rc=0
  local -F start="${EPOCHREALTIME}"
  step::run_isolated check "${name}" "${ARI_DOTFILES_CHECK_TIMEOUT_SECS}" > "${check_file}" 2>> "${log_file}" || rc=$?
  local -i elapsed_ms
  (( elapsed_ms = (EPOCHREALTIME - start) * 1000 ))
  local timed_out=0 verdict_status=""
  if jq -e 'type=="object" and (.status|type)=="string"' "${check_file}" >/dev/null 2>&1; then
    verdict_status="$(jq -r '.status' "${check_file}")"
  fi
  if (( rc == 143 || rc == 137 )); then
    timed_out=1
  elif (( ARI_DOTFILES_CHECK_TIMEOUT_SECS > 0 && elapsed_ms >= ARI_DOTFILES_CHECK_TIMEOUT_SECS * 1000 )) \
       && ! { (( rc == 0 )) && [[ "${verdict_status}" == (ok|warn) ]]; }; then
    # The watchdog fired, so brew under the check was killed; anything but a clean ok/warn reached
    # after that describes the kill, not the machine.
    timed_out=1
  fi
  if (( timed_out )); then
    log::err "check timed out | step='${name}' secs='${ARI_DOTFILES_CHECK_TIMEOUT_SECS}'" 2>> "${log_file}"
    verdict::synth "${name}" error timed_out "timed out after ${ARI_DOTFILES_CHECK_TIMEOUT_SECS}s" > "${check_file}"
  elif (( rc != 0 )) || [[ -z "${verdict_status}" ]]; then
    local tail_text
    tail_text="$(tail_lines "${log_file}" 10)"
    verdict::synth "${name}" error check_crashed "check exited ${rc}${tail_text:+$'\n'}${tail_text}" > "${check_file}"
  fi
  print -r -- "${rc} ${elapsed_ms}"
}

step::record_result() {
  local name="${1}" verdict_file="${2}" rc="${3}" duration_ms="${4}" log_file="${5}" applied_json="${6}"
  jq -c --argjson rc "${rc}" --argjson duration_ms "${duration_ms}" --arg log "${log_file}" --argjson applied "${applied_json}" \
    '. + {rc:$rc, duration_ms:$duration_ms, log:$log, applied:$applied}' "${verdict_file}" > "${RUN_DIR}/${name}.result.json"
}

# A result the runner writes without running the check: a skip, or an error it can see coming.
step::record_synth() {
  local name="${1}" verdict_status="${2}" reason="${3}" detail="${4:-}" log_file="${RUN_DIR}/${1}.log"
  : >> "${log_file}"
  verdict::synth "${name}" "${verdict_status}" "${reason}" "${detail}" > "${RUN_DIR}/${name}.check.json"
  step::record_result "${name}" "${RUN_DIR}/${name}.check.json" 0 0 "${log_file}" false
  run::_log info "${verdict_status} | step='${name}' reason='${reason}'"
}
step::record_skip() { step::record_synth "${1}" skip "${2}"; }

# step::run <name> [attempt]. Reads ARI_DOTFILES_MODE (check|setup), ARI_DOTFILES_DRY_RUN, RUN_DIR. Attempt
# 2 is verify's retry: the check lands in <name>.check.2.json and replaces the result.
# Preflight first: every need must have ended ok or warn, every tool must resolve; then the check;
# then, in setup, the apply and the recheck.
step::run() {
  local name="${1}" attempt="${2:-1}"
  local log_file="${RUN_DIR}/${name}.log" check_file="${RUN_DIR}/${name}.check.json"
  if (( attempt > 1 )); then
    check_file="${RUN_DIR}/${name}.check.${attempt}.json"
  fi
  local need need_status
  for need in ${(s:,:)STEP_NEEDS[${name}]}; do
    need_status="$(step::result_status "${need}")"
    if [[ -n "${need_status}" && "${need_status}" != (ok|warn) ]]; then
      step::record_skip "${name}" "prerequisite_${need_status}"
      return 0
    fi
  done
  local tool
  for tool in ${(s:,:)STEP_TOOLS[${name}]}; do
    if [[ -z "$(probe_tool "${tool}")" ]]; then
      step::record_synth "${name}" error tool_missing "${tool} not found on PATH or under ${ARI_DOTFILES_BREW_PREFIXES:-<no prefixes>}"
      return 0
    fi
  done

  run::_log info "==> ${name}"
  run::_spin "${name} · checking"
  local rc_ms rc duration_ms
  rc_ms="$(step::run_check "${name}" "${check_file}" "${log_file}")"
  rc="${rc_ms%% *}"; duration_ms="${rc_ms##* }"
  local step_status actionable applied=false
  step_status="$(jq -r '.status' "${check_file}")"
  actionable="$(jq -r '.actionable' "${check_file}")"
  run::_log info "check | step='${name}' status='${step_status}' reason='$(jq -r '.reason' "${check_file}")'"

  if [[ "${ARI_DOTFILES_MODE:-check}" == setup && "${actionable}" == true ]] && step::is_fixable "${name}"; then
    if is_dry_run; then
      run::_log info "dry-run, would run apply::${name} | fix='$(jq -r '.fix // ""' "${check_file}")'"
      run::_spin "${name} · planning: $(jq -r '.fix // ""' "${check_file}")"
      # The apply body runs with every mutation logged instead of executed, so the plan it prints is the real one.
      step::run_isolated apply "${name}" 0 >> "${log_file}" 2>&1 || true
      applied='"would_apply"'
    else
      run::_log info "apply::${name}"
      run::_spin "${name} · applying: $(jq -r '.fix // ""' "${check_file}")"
      local apply_rc=0
      step::run_isolated apply "${name}" "${ARI_DOTFILES_APPLY_TIMEOUT_SECS}" >> "${log_file}" 2>&1 || apply_rc=$?
      local -a apply_tail=("${(f)$(tail_lines "${log_file}" 10)}")
      run::_log info "apply done | step='${name}' rc='${apply_rc}'"
      local recheck_file="${RUN_DIR}/${name}.recheck.json"
      run::_spin "${name} · re-checking"
      rc_ms="$(step::run_check "${name}" "${recheck_file}" "${log_file}")"
      rc="${rc_ms%% *}"; duration_ms=$(( duration_ms + ${rc_ms##* } ))
      step_status="$(jq -r '.status' "${recheck_file}")"
      # Still failing, or still asking to be applied (an actionable warn), means the apply did not take.
      if [[ "${step_status}" == (fail|error) || "$(jq -r '.actionable' "${recheck_file}")" == true ]]; then
        jq -c --argjson apply_rc "${apply_rc}" --arg tail "${(F)apply_tail}" \
          '.reason = "apply_did_not_converge" | .apply_rc = $apply_rc
           | .detail = (.detail + "\napply rc=" + ($apply_rc|tostring) + ":\n" + $tail)' \
          "${recheck_file}" > "${check_file}"
      else
        cp "${recheck_file}" "${check_file}"
      fi
      applied=true
    fi
  fi
  step::record_result "${name}" "${check_file}" "${rc}" "${duration_ms}" "${log_file}" "${applied}"
}

# --- Running a selection: the only loop over steps ---

# steps::run_all: every step in `selected`, in order. In setup, once STEP_ABORT_ON has failed or
# errored the rest are recorded as skip/aborted: their tools come from it.
steps::run_all() {
  local aborted=0 name group=""
  for name in "${selected[@]}"; do
    if [[ "${STEP_GROUP[${name}]}" != "${group}" ]]; then
      group="${STEP_GROUP[${name}]}"
      run::_heading "${group}"
    fi
    if (( aborted )); then
      step::record_skip "${name}" aborted
      run::_show "${name}"
      continue
    fi
    step::run "${name}"
    run::_show "${name}"
    if [[ -n "${STEP_ABORT_ON}" && "${name}" == "${STEP_ABORT_ON}" && "${ARI_DOTFILES_MODE}" == setup && "$(step::result_status "${name}")" == (fail|error) ]]; then
      aborted=1
    fi
  done
}

# One retry, after a pause, of every step whose check errored: it absorbs the common transient,
# a brew that was busy when the check started.
steps::retry_errored() {
  local secs="${1}" name
  (( secs > 0 )) || return 0
  local -a errored=()
  for name in "${selected[@]}"; do
    [[ "$(step::result_status "${name}")" == error ]] && errored+=("${name}")
  done
  (( ${#errored} > 0 )) || return 0
  run::_log warn "retrying errored steps | steps='${(j:,:)errored}' secs='${secs}'"
  run::_heading retry
  run::_spin "retrying ${(j:, :)errored} in ${secs}s"
  sleep "${secs}"
  for name in "${errored[@]}"; do
    step::run "${name}" 2
    run::_show "${name}"
  done
}

# --- How a run is shown ---
# Plain (no tty, NO_COLOR, launchd, --json): the runner's log lines on stderr and the table at the
# end, as always. Fancy: a header, a dim heading per group, a spinner while a step works, then one
# line per step on stdout and the painted roll-up. The log lines land in $RUN_DIR/run.log either way.

typeset -g RUN_JSON=0 RUN_T0="" RUN_NAME_W=0

run::is_fancy() { (( ! RUN_JSON )) && ui::is_fancy; }

# A runner log line: appended to run.log (plain text, timestamped), and on stderr unless fancy.
run::_log() {
  local tier="${1}"; shift
  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
    run::_log_file "${tier}" "$@" 2>> "${RUN_DIR}/run.log"
  fi
  run::is_fancy || "log::${tier}" "$@"
}
run::_log_file() {
  local c_green="" c_yellow="" c_red="" c_grey="" c_cyan="" c_rst=""
  LOG_PREAMBLE=1 "log::${1}" "${@:2}"
}

run::_spin() { run::is_fancy || return 0; ui::spin_start "${1}"; }

# The verb comes from the caller (RUN_VERB) or dispatch's `verb`; the mode when neither is set.
run::_header() {
  run::is_fancy || return 0
  local mode="${1}" name text
  RUN_NAME_W=0
  for name in "${selected[@]}"; do (( ${#name} > RUN_NAME_W )) && RUN_NAME_W=${#name}; done
  text="${RUN_VERB:-${verb:-${mode}}} · $(plural "${#selected}" step steps)"
  is_dry_run && text+=" · dry-run"
  ui::paint bold "${text}"
  trap 'run::_interrupted' INT TERM HUP
}

run::_heading() { run::is_fancy || return 0; ui::spin_stop; ui::paint grey "${1}"; }

# Ctrl-C mid-step: the spinner goes, the cursor comes back, the lock is released, and the step's
# processes go too. The $(…) around a check dies of the signal first, so the check and its
# watchdog (& jobs, which ignore SIGINT) are orphans by now: when the run leads its process group,
# as a terminal job does, the group is TERMed, else each child tree is.
run::_interrupted() {
  zmodload -F zsh/system p:sysparams 2>/dev/null || true
  [[ "${sysparams[pid]:-$$}" == "$$" ]] || exit 130
  trap '' INT TERM HUP
  ui::spin_stop
  print -nu2 -- $'\e[?25h'
  local pgid
  pgid="$(ps -o pgid= -p "$$" 2>/dev/null || true)"
  if [[ "${pgid//[[:space:]]/}" == "$$" ]]; then
    pkill -TERM -g "$$" 2>/dev/null || true
  else
    local child
    for child in ${(f)"$(pgrep -P "$$" 2>/dev/null || true)"}; do kill_tree TERM "${child}"; done
  fi
  lock::release
  print -u2 -- "interrupted"
  exit 130
}

# One line for a finished step: glyph, name, reason, the detail's first line clipped to the
# terminal, the duration in grey; a fail or error adds the step log's path.
run::_show() {
  run::is_fancy || return 0
  ui::spin_stop
  local name="${1}" file="${RUN_DIR}/${1}.result.json"
  [[ -f "${file}" ]] || return 0
  local st reason applied ms fix log_path detail
  IFS=$'\x1f' read -r st reason applied ms fix log_path detail < <(jq -r '[.status, .reason,
      (.applied|tostring), (.duration_ms|tostring), (.fix // ""), (.log // ""),
      ((.detail // "") | split("\n")[0])] | join("\u001f")' "${file}")
  if [[ "${applied}" == true && "${st}" == (ok|warn) ]]; then reason=applied; fi
  if [[ "${applied}" == would_apply ]]; then detail="would apply: ${fix:-apply::${name}}"; fi
  local dur prefix suffix rpad
  printf -v dur '%.1fs' $(( ${ms:-0} / 1000.0 ))
  printf -v rpad '%-24s' "${reason}"
  printf -v prefix '%s %-*s %s ' "$(ui::glyph "${st}")" "${RUN_NAME_W}" "${name}" "${rpad}"
  suffix="  ${dur}"
  local -i room
  room=$(( $(ui::cols) - ${#prefix} - ${#suffix} ))
  detail="$(ui::clip "${room}" "${detail}")"
  printf -v prefix '%s %-*s %s ' "$(ui::paint "${st}" "$(ui::glyph "${st}")")" "${RUN_NAME_W}" "${name}" \
    "$(ui::paint "${st}" "${rpad}")"
  print -r -- "${prefix}${detail}$(ui::paint grey "${suffix}")"
  if [[ "${st}" == (fail|error) ]]; then ui::paint grey "  log: ${log_path}"; fi
}

# The end of a fancy run: the roll-up painted in its status's colour, then the total time.
run::_rollup() {
  local summary="${RUN_DIR}/summary.json" st counts took=""
  st="$(jq -r '.status' "${summary}")"
  counts="$(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' "${summary}")"
  [[ -z "${RUN_T0}" ]] || took="  $(elapsed "${RUN_T0}")s"
  print -r -- "$(ui::paint "${st}" "status: ${st} (${counts})")$(ui::paint grey "${took}")"
}

# --- A run: begin, summarize, end ---

# RUN_ID derives from ARI_DOTFILES_NOW alone (the report marker depends on it), so a rerun in the
# same second reuses the directory; wiping it keeps stale artifacts out of the summary. Only a
# directory under <state>/runs/ is ever removed.
run::begin() {
  local mode="${1}"
  export ARI_DOTFILES_MODE="${mode}"
  if [[ "${RUN_DIR}" == "${ARI_DOTFILES_STATE_DIR}/runs/"?* ]]; then
    rm -rf -- "${RUN_DIR}"
  fi
  mkdir -p "${RUN_DIR}"
  RUN_T0="${EPOCHREALTIME}"
  ui::is_fancy || true   # decided here, before any $(…), so every capture inherits the answer
  run::_header "${mode}"
  if is_dry_run; then
    run::_log warn "dry-run: no changes will be made"
  fi
  run::_log info "run | mode='${mode}' run_id='${RUN_ID}' run_dir='${RUN_DIR}' steps='${(j:,:)selected}'"
}

# summary.json (schema 1, roll-up error > fail > warn > ok) → last-<mode>.json; old runs pruned to 8.
run::summarize() {
  local ts name
  strftime -s ts '%Y-%m-%dT%H:%M:%S%z' "${ARI_DOTFILES_NOW}"
  local -a result_files=()
  for name in "${STEPS[@]}"; do
    if [[ -f "${RUN_DIR}/${name}.result.json" ]]; then
      result_files+=("${RUN_DIR}/${name}.result.json")
    fi
  done
  local -a brew_arg=(--argjson brew '[null]')
  if [[ -s "${RUN_DIR}/drift.json" ]]; then
    brew_arg=(--slurpfile brew "${RUN_DIR}/drift.json")
  fi
  jq -n --arg run_id "${RUN_ID}" --arg host "${ARI_DOTFILES_HOST}" --arg mode "${ARI_DOTFILES_MODE}" --arg ts "${ts}" \
        --slurpfile steps <(cat -- "${result_files[@]}") "${brew_arg[@]}" '
    ($steps | map(.status)) as $s
    | {schema: 1, run_id: $run_id, ts: $ts, host: $host, mode: $mode,
       status: (if any($s[]; .=="error") then "error" elif any($s[]; .=="fail") then "fail"
                elif any($s[]; .=="warn") then "warn" else "ok" end),
       counts: ($steps | group_by(.status) | map({(.[0].status): length}) | add // {}),
       steps: $steps, brew: ($brew[0] // null)}' > "${RUN_DIR}/summary.json"
  cp "${RUN_DIR}/summary.json" "${ARI_DOTFILES_STATE_DIR}/last-${ARI_DOTFILES_MODE}.json"
  local -a runs=("${ARI_DOTFILES_STATE_DIR}"/runs/*(N/On))
  local dir
  for dir in "${runs[@]:8}"; do
    rm -rf -- "${dir}"
  done
}

run::print_human() {
  local summary="${RUN_DIR}/summary.json"
  if run::is_fancy; then run::_rollup; return 0; fi
  local step_status step reason detail applied
  while IFS=$'\t' read -r step_status step reason applied detail; do
    if [[ "${applied}" == would_apply ]]; then
      printf '%-6s %-22s %-26s would run apply::%s  %s\n' "${step_status}" "${step}" "${reason}" "${step}" "${detail}"
    else
      printf '%-6s %-22s %-26s %s\n' "${step_status}" "${step}" "${reason}" "${detail}"
    fi
  done < <(jq -r '.steps[] | [.status, .step, .reason, (.applied|tostring), (.detail | split("\n")[0])] | @tsv' "${summary}")
  print -r -- "status: $(jq -r '.status' "${summary}") ($(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' "${summary}"))"
}

# Manual items are told to the human once, at the end, where they will be read. Details span
# lines, so each record travels as one JSON string per line.
run::print_manual() {
  local summary="${RUN_DIR}/summary.json"
  local encoded
  while IFS= read -r encoded; do
    log::WARN "$(jq -rn --argjson block "${encoded}" '$block')"
  done < <(jq -r '.steps[] | select(.manual and (.status=="warn" or .status=="fail")) | "Manual step (\(.step) \(.reason)):\n\(.detail)" | @json' "${summary}")
}

# Prints the run (JSON or the human table) and ends the process.
run::end() {
  local json="${1:-0}"
  if (( json )); then
    cat "${RUN_DIR}/summary.json"
  else
    run::print_human
    run::print_manual
  fi
  run::exit
}

# Ends the process with the run's exit code. Explicit, because zsh skips the EXIT trap when
# ERR_EXIT ends the shell (a nonzero return out of main included), which would leak the lock.
run::exit() {
  local run_status rc=0
  run_status="$(jq -r '.status' "${RUN_DIR}/summary.json")"
  verdict::exit_code "${run_status}" || rc=$?
  exit "${rc}"
}
