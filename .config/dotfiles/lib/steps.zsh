# dotfiles/lib/steps.zsh — steps as data, one runner.
#
# A step is one file, steps/<name>.zsh, that declares itself and defines its functions:
#
#   # step <name> — <summary>       line 1 of the file
#   step::declare <name> [--group repo|brew|tools] [--needs a,b] [--tools t,u] --desc D
#                 [--apply "<what the apply changes>"] [--abort]
#   step::watches <name> <glob>.. | step::watches <name> --none "<why it reads no repo file>"
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
zmodload zsh/mapfile
zmodload -F zsh/files b:zf_rm

typeset -ga STEPS=() STEPS_DECLARED=()
typeset -gA STEP_GROUP=() STEP_NEEDS=() STEP_TOOLS=() STEP_DESC=() STEP_FILE=() STEP_PATH=() STEP_APPLY_DOC=()
# The documentation rule's gaps, filled by steps::validate (steps::doc_gaps): step -> what it lacks
# (phrases joined by ", "), and step -> the same as short keys (header,--desc,--apply,watches).
# A gap is never a load error: the dotfiles_docs step flags it.
typeset -gA STEP_UNDOCUMENTED=() STEP_DOC_KEYS=()
typeset -ga STEP_GROUPS=(repo brew tools)   # run order of the groups
typeset -g STEP_ABORT_ON=""                  # in setup, a fail or error here skips every later step

# --- Registry ---

step::declare() {
  local name="${1:?step::declare needs a name}"; shift
  local group=tools needs="" tools="" desc="" abort=0
  unset "STEP_APPLY_DOC[${name}]"
  while (( $# )); do case "${1}" in
    --group) group="${2}"; shift 2 ;;
    --needs) needs="${2}"; shift 2 ;;
    --tools) tools="${2}"; shift 2 ;;
    --desc)  desc="${2}"; shift 2 ;;
    --apply) STEP_APPLY_DOC[${name}]="${2}"; shift 2 ;;
    --abort) abort=1; shift ;;
    *) print -u2 "[ERROR] step::declare: bad flag | step='${name}' flag='${1}'"; return 64 ;;
  esac; done
  (( ${STEPS_DECLARED[(Ie)${name}]} )) || STEPS_DECLARED+=("${name}")
  STEP_GROUP[${name}]="${group}"; STEP_NEEDS[${name}]="${needs}"; STEP_TOOLS[${name}]="${tools}"; STEP_DESC[${name}]="${desc}"
  STEP_PATH[${name}]="${funcfiletrace[1]%:*}"           # the file that declared it
  STEP_FILE[${name}]="${STEP_PATH[${name}]:t:r}"
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
# groups are known; needs are known and in the same or an earlier group. Then the documentation
# rule (steps::doc_gaps), which never fails the load.
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
  steps::doc_gaps
  return "${rc}"
}

# The documentation rule, per declared step, into STEP_UNDOCUMENTED and STEP_DOC_KEYS; no fork
# (one builtin read of each file's first line):
#   header    line 1 is '# step <name> — <summary>'
#   --desc    a non-empty --desc
#   --apply   a non-empty --apply "<what the apply changes>" exactly when apply::<name> exists
#   watches   step::watches <name> <glob>.., or step::watches <name> --none "<why>"
steps::doc_gaps() {
  local name line want doc
  local -a gaps keys
  STEP_UNDOCUMENTED=() STEP_DOC_KEYS=()
  for name in "${STEPS_DECLARED[@]}"; do
    gaps=() keys=() line=""
    want="# step ${name} — "
    { IFS= read -r line < "${STEP_PATH[${name}]}" } 2>/dev/null || true
    if [[ "${line}" != "${want}"* || -z "${${line#"${want}"}//[[:space:]]/}" ]]; then
      gaps+=("line 1 is not '# step ${name} — <summary>'"); keys+=(header)
    fi
    [[ -n "${STEP_DESC[${name}]//[[:space:]]/}" ]] || { gaps+=("no --desc"); keys+=(--desc); }
    if (( ${+functions[apply::${name}]} )); then
      doc="${STEP_APPLY_DOC[${name}]:-}"
      [[ -n "${doc//[[:space:]]/}" ]] || { gaps+=("no --apply \"<what the apply changes>\""); keys+=(--apply); }
    elif (( ${+STEP_APPLY_DOC[${name}]} )); then
      gaps+=("--apply but no apply::${name}"); keys+=(--apply)
    fi
    if (( ${+STEP_WATCH_NONE[${name}]} )); then
      if [[ -n "${STEP_WATCHES[${name}]:-}" ]]; then gaps+=("step::watches has both globs and --none"); keys+=(watches)
      elif [[ -z "${STEP_WATCH_NONE[${name}]//[[:space:]]/}" ]]; then gaps+=("step::watches --none without a reason"); keys+=(watches)
      fi
    elif [[ -z "${STEP_WATCHES[${name}]:-}" ]]; then
      gaps+=("no step::watches (globs or --none \"<why it reads no repo file>\")"); keys+=(watches)
    fi
    (( ${#gaps} )) || continue
    STEP_UNDOCUMENTED[${name}]="${(j:, :)gaps}"
    STEP_DOC_KEYS[${name}]="${(j:,:)keys}"
  done
  return 0
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

# name · group · needs · tools · apply · docs (ok, or the keys of what is missing) · description,
# one line per step.
steps::list() {
  local name has_apply
  for name in "${STEPS[@]}"; do
    has_apply=no; step::is_fixable "${name}" && has_apply=yes
    printf '%-22s %-6s %-14s %-6s %-5s %-8s %s\n' "${name}" "${STEP_GROUP[${name}]}" "${STEP_NEEDS[${name}]:--}" "${STEP_TOOLS[${name}]:--}" "${has_apply}" "${STEP_DOC_KEYS[${name}]:-ok}" "${STEP_DESC[${name}]}"
  done
}

# --- Running one step ---

# Prints a step's recorded status. A result the runner wrote from a verdict starts
# {"step":"<name>","status":"<status>", (verdict and verdict::synth put those keys first), so the
# status is read without a jq; any other shape goes through jq.
step::result_status() {
  local file="${RUN_DIR}/${1}.result.json" json prefix
  [[ -f "${file}" ]] || return 0
  json="${mapfile[${file}]-}"
  prefix="{\"step\":\"${1}\",\"status\":\""
  if [[ "${json}" == "${prefix}"[a-z]*\"* ]]; then
    json="${json#"${prefix}"}"
    print -r -- "${json%%\"*}"
    return 0
  fi
  jq -r '.status' "${file}"
}

# Runs one check::/apply:: in a fresh zsh that sources the kernel and the step's file, under the
# watchdog. The function name travels in $STEP so no shell quoting of the name is needed; colours
# are off there so the step logs stay plain. zsh -f: the step sees only what the kernel and the
# exported environment give it, not ~/.zshenv, which costs a source per step and is not an input.
step::run_isolated() {
  local kind="${1}" name="${2}" timeout_secs="${3}"
  export STEP="${name}"
  local -x NO_COLOR=1
  with_timeout "${timeout_secs}" zsh -f -c '
    set -euo pipefail
    for f in "${ARI_DOTFILES_LIB}"/*.zsh(N); do source "${f}"; done
    source "${ARI_DOTFILES_STEPS}/${STEP}.zsh"
    "'"${kind}"'::${STEP}"'
}

# One jq over a check file: when it holds one verdict object with a string status, prints its
# status, actionable and reason joined by \x1f; then that record's run::_show fields (empty when
# they do not render); then the result record the runner stores when no apply follows (the
# verdict plus rc, duration_ms, log and applied=false, as step::record_result writes it); each on
# its own line. Else nothing.
step::_digest() {
  local file="${1}" rc="${2}" duration_ms="${3}" log_file="${4}"
  jq -rs --argjson rc "${rc}" --argjson duration_ms "${duration_ms}" --arg log "${log_file}" '
    if length == 1 and (.[0] | type == "object" and (.status | type) == "string") then .[0]
      | (. + {rc: $rc, duration_ms: $duration_ms, log: $log, applied: false}) as $record
      | ([.status, (.actionable | tostring), (.reason | tostring)] | join("\u001f")),
        ($record | try ('"${RUN_SHOW_FIELDS}"' | split("\n")[0]) catch ""),
        ($record | tojson)
    else empty end' "${file}" 2>/dev/null || true
}

# Runs the check, normalizing crashes and timeouts into error verdicts in <check_file>. Prints
# `<rc> <ms>`, then step::_digest of the final check file: its status, actionable and reason,
# and on the last line the record to store when no apply follows.
step::run_check() {
  local name="${1}" check_file="${2}" log_file="${3}"
  local rc=0
  local -F start="${EPOCHREALTIME}"
  step::run_isolated check "${name}" "${ARI_DOTFILES_CHECK_TIMEOUT_SECS}" > "${check_file}" 2>> "${log_file}" || rc=$?
  local -i elapsed_ms
  (( elapsed_ms = (EPOCHREALTIME - start) * 1000 ))
  local timed_out=0 verdict_status="" digest
  digest="$(step::_digest "${check_file}" "${rc}" "${elapsed_ms}" "${log_file}")"
  [[ -z "${digest}" ]] || verdict_status="${digest%%$'\x1f'*}"
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
  if (( timed_out )) || (( rc != 0 )) || [[ -z "${verdict_status}" ]]; then
    digest="$(step::_digest "${check_file}" "${rc}" "${elapsed_ms}" "${log_file}")"
  fi
  print -r -- "${rc} ${elapsed_ms}"
  print -r -- "${digest}"
}

step::record_result() {
  local name="${1}" verdict_file="${2}" rc="${3}" duration_ms="${4}" log_file="${5}" applied_json="${6}"
  jq -c --argjson rc "${rc}" --argjson duration_ms "${duration_ms}" --arg log "${log_file}" --argjson applied "${applied_json}" \
    '. + {rc:$rc, duration_ms:$duration_ms, log:$log, applied:$applied}' "${verdict_file}" > "${RUN_DIR}/${name}.result.json"
  run::_keep_show "${name}" ""
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
  local tool REPLY
  for tool in ${(s:,:)STEP_TOOLS[${name}]}; do
    probe_tool::reply "${tool}"
    if [[ -z "${REPLY}" ]]; then
      step::record_synth "${name}" error tool_missing "${tool} not found on PATH or under ${ARI_DOTFILES_BREW_PREFIXES:-<no prefixes>}"
      return 0
    fi
  done

  run::_log info "==> ${name}"
  run::_spin "${name} · checking"
  local out rc_ms rc duration_ms record fields show
  out="$(step::run_check "${name}" "${check_file}" "${log_file}")"
  rc_ms="${out%%$'\n'*}"; out="${out#*$'\n'}"
  rc="${rc_ms%% *}"; duration_ms="${rc_ms##* }"
  fields="${out%%$'\n'*}"; out="${out#*$'\n'}"
  show="${out%%$'\n'*}"; record="${out#*$'\n'}"
  local step_status actionable reason applied=false
  step_status="${fields%%$'\x1f'*}"; fields="${fields#*$'\x1f'}"
  actionable="${fields%%$'\x1f'*}"; reason="${fields#*$'\x1f'}"
  run::_log info "check | step='${name}' status='${step_status}' reason='${reason}'"

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
      out="$(step::run_check "${name}" "${recheck_file}" "${log_file}")"
      rc_ms="${out%%$'\n'*}"; fields="${${out#*$'\n'}%%$'\n'*}"
      rc="${rc_ms%% *}"; duration_ms=$(( duration_ms + ${rc_ms##* } ))
      step_status="${fields%%$'\x1f'*}"; fields="${fields#*$'\x1f'}"
      actionable="${fields%%$'\x1f'*}"
      # Still failing, or still asking to be applied (an actionable warn), means the apply did not take.
      if [[ "${step_status}" == (fail|error) || "${actionable}" == true ]]; then
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
  if [[ "${applied}" == false ]]; then
    print -r -- "${record}" > "${RUN_DIR}/${name}.result.json"
    run::_keep_show "${name}" "${show}"
  else
    step::record_result "${name}" "${check_file}" "${rc}" "${duration_ms}" "${log_file}" "${applied}"
  fi
}

# --- Running a selection: the only loop over steps ---

# steps::run_all: every step in `selected`, in order. In setup, once STEP_ABORT_ON has failed or
# errored the rest are recorded as skip/aborted: their tools come from it. A check-mode run
# (steps::is_parallel) runs the checks of a group side by side instead (steps::run_all_parallel).
steps::run_all() {
  if steps::is_parallel; then steps::run_all_parallel; return; fi
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

# --- Checks side by side ---
# In check mode a check only reads, so the checks of one group run at once: each step::run in a
# background subshell whose runner log lines (run.log and stderr) are buffered, then replayed in
# run order as each is waited for. The lines, the logs and the results are what a serial run
# writes; only the wall time changes. A step starts once the steps it needs have finished, and
# a step that uses brew (the brew group, or --tools brew) runs alone: brew holds a lock.
# Setup mode (apply, init) and ARI_DOTFILES_SERIAL=1 run one step at a time.
typeset -ga STEP_PENDING=()      # launched and not yet shown, in run order
typeset -gA STEP_JOB=()          # step -> pid of its background step::run
typeset -g RUN_BUFFER=""         # in a background step: the file its run.log lines go to

steps::is_parallel() { [[ "${ARI_DOTFILES_MODE:-check}" != setup && "${ARI_DOTFILES_SERIAL:-0}" != 1 ]]; }
step::is_serial() { [[ "${STEP_GROUP[${1}]}" == brew || ",${STEP_TOOLS[${1}]}," == *,brew,* ]]; }

step::launch() {
  local name="${1}"
  ( RUN_BUFFER="${RUN_DIR}/.${name}.run.log"; : > "${RUN_BUFFER}"; step::run "${name}" ) 2> "${RUN_DIR}/.${name}.stderr" &
  STEP_JOB[${name}]=$!
  STEP_PENDING+=("${name}")
}

# Waits for the launched steps in run order, up to and including <name> (every one when no name
# is given), replaying each one's buffered log lines and showing its line. The spinner names the
# step being waited for, one per check as in a serial run.
steps::drain() {
  local upto="${1:-}" name pid buf
  zmodload -F zsh/files b:zf_rm
  while (( ${#STEP_PENDING} )); do
    name="${STEP_PENDING[1]}"; shift STEP_PENDING
    pid="${STEP_JOB[${name}]}"
    run::_spin "${name} · checking"
    wait "${pid}" 2>/dev/null || true
    buf="${RUN_DIR}/.${name}.run.log"
    if [[ -f "${buf}" ]]; then print -rn -- "${mapfile[${buf}]-}" >> "${RUN_DIR}/run.log"; zf_rm -f -- "${buf}"; fi
    buf="${RUN_DIR}/.${name}.stderr"
    if [[ -f "${buf}" ]]; then print -rnu2 -- "${mapfile[${buf}]-}"; zf_rm -f -- "${buf}"; fi
    run::_show "${name}"
    [[ "${name}" != "${upto}" ]] || break
  done
}

steps::run_all_parallel() {
  local name group="" need
  STEP_PENDING=() STEP_JOB=()
  for name in "${selected[@]}"; do
    if [[ "${STEP_GROUP[${name}]}" != "${group}" ]]; then
      steps::drain
      group="${STEP_GROUP[${name}]}"
      run::_heading "${group}"
    fi
    for need in ${(s:,:)STEP_NEEDS[${name}]}; do
      if (( ${STEP_PENDING[(Ie)${need}]} )); then steps::drain "${need}"; fi
    done
    if step::is_serial "${name}"; then
      steps::drain
      step::run "${name}"
      run::_show "${name}"
    else
      step::launch "${name}"
    fi
  done
  steps::drain
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
# end, as always. Fancy: a header, a bold heading and rule per group, a spinner while a step works, then one
# line per step on stdout and the painted roll-up. The log lines land in $RUN_DIR/run.log either way.

typeset -g RUN_JSON=0 RUN_T0="" RUN_NAME_W=0 RUN_BEGAN_SECS=0

run::is_fancy() { (( ! RUN_JSON )) && ui::is_fancy; }

# A runner log line: appended to run.log (plain text, timestamped), and on stderr unless fancy.
run::_log() {
  local tier="${1}"; shift
  if [[ -n "${RUN_BUFFER}" ]]; then
    run::_log_file "${tier}" "$@" 2>> "${RUN_BUFFER}"
  elif [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
    run::_log_file "${tier}" "$@" 2>> "${RUN_DIR}/run.log"
  fi
  run::is_fancy || "log::${tier}" "$@"
}
run::_log_file() {
  local c_green="" c_yellow="" c_red="" c_grey="" c_cyan="" c_rst=""
  LOG_PREAMBLE=1 "log::${1}" "${@:2}"
}

run::_spin() { [[ -z "${RUN_BUFFER}" ]] && run::is_fancy || return 0; ui::spin_start "${1}"; }

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

# A group's heading: its name in bold, then a grey rule across the terminal (ui::rule).
run::_heading() { run::is_fancy || return 0; ui::spin_stop; ui::rule "${1}"; }

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

# The fields run::_show reads from a result record, joined by \x1f, as one jq expression: the
# runner's digest computes them with the record, and run::_show falls back to it on the file.
typeset -g RUN_SHOW_FIELDS='[.status, .reason, (.applied|tostring), (.duration_ms|tostring),
  (.fix // ""), (.log // ""), ((.detail // "") | split("\n")[0])] | join("\u001f")'

# Fancy: keeps the show fields the digest computed for <name>'s result next to it, so run::_show
# needs no jq of its own; a step that ran in the background hands them over through the file.
run::_keep_show() {
  local file="${RUN_DIR}/.${1}.show"
  if run::is_fancy && [[ -n "${2}" ]]; then print -r -- "${2}" > "${file}"
  elif [[ -e "${file}" ]]; then zf_rm -f -- "${file}"
  fi
}

# One line for a finished step: glyph, name, reason, the detail's first line clipped to the
# terminal, the duration in grey; a fail or error adds the step log's path. Paths as ui::paths shows them.
run::_show() {
  run::is_fancy || return 0
  ui::spin_stop
  local name="${1}" file="${RUN_DIR}/${1}.result.json" kept="${RUN_DIR}/.${1}.show" line
  [[ -f "${file}" ]] || return 0
  if [[ -f "${kept}" ]]; then
    line="${mapfile[${kept}]-}"; zf_rm -f -- "${kept}"
  else
    line="$(jq -r "${RUN_SHOW_FIELDS}" "${file}")"
  fi
  local st reason applied ms fix log_path detail
  IFS=$'\x1f' read -r st reason applied ms fix log_path detail <<< "${line%%$'\n'*}"
  if [[ "${applied}" == true && "${st}" == (ok|warn) ]]; then reason=applied; fi
  if [[ "${applied}" == would_apply ]]; then detail="would apply: ${fix:-apply::${name}}"; fi
  local dur prefix suffix rpad
  printf -v dur '%.1fs' $(( ${ms:-0} / 1000.0 ))
  printf -v rpad '%-24s' "${reason}"
  printf -v prefix '%s %-*s %s ' "$(ui::glyph "${st}")" "${RUN_NAME_W}" "${name}" "${rpad}"
  suffix="  ${dur}"
  local -i room
  room=$(( $(ui::cols) - ${#prefix} - ${#suffix} ))
  local REPLY
  ui::_paths "${detail}"
  detail="$(ui::clip "${room}" "${REPLY}")"
  printf -v prefix '%s %-*s %s ' "$(ui::paint "${st}" "$(ui::glyph "${st}")")" "${RUN_NAME_W}" "${name}" \
    "$(ui::paint "${st}" "${rpad}")"
  print -r -- "${prefix}${detail}$(ui::paint grey "${suffix}")"
  if [[ "${st}" == (fail|error) ]]; then ui::_paths "${log_path}"; ui::paint grey "  log: ${REPLY}"; fi
}

# The end of a fancy run: the roll-up painted in its status's colour, then the total time, then
# what needs attention (run::_attention_box).
run::_rollup() {
  local summary="${RUN_DIR}/summary.json" st counts took=""
  st="$(jq -r '.status' "${summary}")"
  counts="$(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' "${summary}")"
  [[ -z "${RUN_T0}" ]] || took="  $(elapsed "${RUN_T0}")s"
  print -r -- "$(ui::paint "${st}" "status: ${st} (${counts})")$(ui::paint grey "${took}")"
  run::_attention_box "${st}"
}

# What needs attention, one record per step on stdout, fields joined by \x1f:
# status, step, reason, fix, manual, detail (as a JSON string, since it spans lines).
# A step needs attention when it failed or errored, warned with a fix, or is manual (warn or fail).
# The fix is the verdict's; an actionable step without one gets `dotfiles apply <step>`; a manual
# step without one is done by hand; anything else points at its log.
run::_attention() {
  jq -r --arg cli "${CLI_NAME}" '.steps[]
    | select(.status == "fail" or .status == "error"
             or (.status == "warn" and ((.fix // "") != "" or .manual)))
    | [.status, .step, .reason,
       (if (.fix // "") != "" then .fix
        elif .actionable then "\($cli) apply \(.step)"
        elif .manual then "by hand"
        else "see \(.log // "the run log")" end),
       (.manual|tostring), ((.detail // "") | tojson)]
    | join("\u001f")' "${RUN_DIR}/summary.json"
}

# Plain: `fix    <step>  <fix>` per step that needs attention, after the status line.
run::_fix_lines() {
  local st step reason fix manual detail REPLY
  while IFS=$'\x1f' read -r st step reason fix manual detail; do
    ui::_cmd_paths "${fix}"
    print -r -- "fix    ${step}  ${REPLY}"
  done < <(run::_attention)
}

# Fancy: a box titled with the count, bordered in the roll-up's colour: per step its glyph, name
# and reason, the fix, and a manual step's detail (clipped); the run directory last. Nothing needs
# attention: one green line instead.
run::_attention_box() {
  local rollup="${1}" st step reason fix manual detail line REPLY
  local -a body=() lines
  local -i n=0 width
  width=$(( $(ui::cols) - 4 ))
  while IFS=$'\x1f' read -r st step reason fix manual detail; do
    (( ++n ))
    body+=("$(ui::paint "${st}" "$(ui::glyph "${st}")") ${step}  $(ui::paint "${st}" "${reason}")")
    ui::_cmd_paths "${fix}"
    body+=("  fix: ${REPLY}")   # a command to copy, so never clipped
    if [[ "${manual}" == true ]]; then
      lines=("${(@f)$(jq -rn --argjson d "${detail}" '$d')}")
      for line in "${lines[@]}"; do
        ui::_paths "${line}"; line="${REPLY}"
        if [[ -n "${line}" ]]; then body+=("$(ui::paint grey "$(ui::clip "${width}" "    ${line}")")"); fi
      done
    fi
  done < <(run::_attention)
  if (( n == 0 )); then
    local total
    total="$(jq -r '.steps | length' "${RUN_DIR}/summary.json")"
    if [[ "${rollup}" == ok ]]; then ui::paint ok "$(ui::glyph ok) all $(plural "${total}" step steps) ok"
    else ui::paint ok "$(ui::glyph ok) nothing to fix"
    fi
    return 0
  fi
  ui::_paths "${RUN_DIR}"
  body+=("$(ui::paint grey "run: ${REPLY}")")
  local verb_s=need
  (( n > 1 )) || verb_s=needs
  ui::box --title "${n} ${verb_s} attention" --color "${rollup}" -- "${body[@]}"
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
  RUN_T0="${EPOCHREALTIME}" RUN_BEGAN_SECS="${EPOCHSECONDS}"
  ui::is_fancy || true   # decided here, before any $(…), so every capture inherits the answer
  run::_header "${mode}"
  if is_dry_run; then
    run::_log warn "dry-run: no changes will be made"
  fi
  run::_log info "run | mode='${mode}' run_id='${RUN_ID}' run_dir='${RUN_DIR}' steps='${(j:,:)selected}'"
}

# A second run in the same process (init --edit's setup after its checks) needs a run id of its
# own: RUN_ID comes from ARI_DOTFILES_NOW, and run::begin wipes RUN_DIR. The clock moves on by the
# time since the first run began (at least a second), past any run directory already there, and
# RUN_ID, RUN_DIR and ARI_DOTFILES_NOW follow it.
run::next_id() {
  local -i now
  now=$(( ARI_DOTFILES_NOW + (RUN_BEGAN_SECS > 0 && EPOCHSECONDS > RUN_BEGAN_SECS ? EPOCHSECONDS - RUN_BEGAN_SECS : 0) ))
  (( now > ARI_DOTFILES_NOW )) || now=$(( ARI_DOTFILES_NOW + 1 ))
  while [[ -e "${ARI_DOTFILES_STATE_DIR}/runs/$(run_id "${now}")" ]]; do now=$(( now + 1 )); done
  export ARI_DOTFILES_NOW="${now}"
  RUN_ID="$(run_id "${now}")"
  RUN_DIR="${ARI_DOTFILES_STATE_DIR}/runs/${RUN_ID}"
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
  local step_status step reason detail applied REPLY
  while IFS=$'\t' read -r step_status step reason applied detail; do
    ui::_paths "${detail}"; detail="${REPLY}"
    if [[ "${applied}" == would_apply ]]; then
      printf '%-6s %-22s %-26s would run apply::%s  %s\n' "${step_status}" "${step}" "${reason}" "${step}" "${detail}"
    else
      printf '%-6s %-22s %-26s %s\n' "${step_status}" "${step}" "${reason}" "${detail}"
    fi
  done < <(jq -r '.steps[] | [.status, .step, .reason, (.applied|tostring), (.detail | split("\n")[0])] | @tsv' "${summary}")
  print -r -- "status: $(jq -r '.status' "${summary}") ($(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' "${summary}"))"
  run::_fix_lines
}

# Manual items are told to the human once, at the end, where they will be read. Details span
# lines, so each record travels as one JSON string per line. A fancy run has them in its box.
run::print_manual() {
  local summary="${RUN_DIR}/summary.json"
  ! run::is_fancy || return 0
  local encoded
  while IFS= read -r encoded; do
    log::WARN "$(jq -rn --argjson block "${encoded}" '$block')"
  done < <(jq -r '.steps[] | select(.manual and (.status=="warn" or .status=="fail")) | "Manual step (\(.step) \(.reason)):\n\(.detail)" | @json' "${summary}")
}

# Prints the run: summary.json, or the human table and the manual items.
run::print_end() {
  if (( ${1:-0} )); then
    cat "${RUN_DIR}/summary.json"
  else
    run::print_human
    run::print_manual
  fi
}

# Prints the run and ends the process.
run::end() {
  run::print_end "${1:-0}"
  run::exit
}

# Returns the run's exit code (verdict::exit_code of the roll-up), for a caller that goes on.
run::exit_code() {
  local run_status
  run_status="$(jq -r '.status' "${RUN_DIR}/summary.json")"
  verdict::exit_code "${run_status}"
}

# Ends the process with the run's exit code. Explicit, because zsh skips the EXIT trap when
# ERR_EXIT ends the shell (a nonzero return out of main included), which would leak the lock.
run::exit() {
  local rc=0
  run::exit_code || rc=$?
  exit "${rc}"
}
