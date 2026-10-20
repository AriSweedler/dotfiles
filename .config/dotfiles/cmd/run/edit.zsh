# dotfiles/cmd/run/edit.zsh — the plan file `init --edit`, `apply --edit` and `healthcheck --edit`
# open in $EDITOR: one `apply|skip <step>  # …` line per step that may be chosen. Loaded by
# need_lib; defines functions only.
#
# A plan is written from a basis (what each step's last result was): a check run's summary for
# init and healthcheck (runplan::basis_summary), each step's newest result for apply
# (runplan::basis_runs). runplan::edit opens it, parses every line on save (runplan::parse) and
# fills the caller's `chosen` (the apply lines' steps) and `planned` (every step line's step).
# The editor never runs under the lock, the INT trap or a spinner: runplan::release lets them go.

# The basis, per step: last status, reason, fix, the detail's first line, actionable, manual; and
# the age of the result (apply's plan only).
typeset -gA PLAN_STATUS=() PLAN_REASON=() PLAN_FIX=() PLAN_DETAIL=() PLAN_ACTIONABLE=() PLAN_MANUAL=() PLAN_AGE=()
typeset -gA PLAN_LINE=()      # step -> its line number in the plan last parsed
typeset -ga PLAN_OFFER=()     # the steps an apply line may name (init, healthcheck)
typeset -g PLAN_ANY=0         # 1: an apply line may name any step (apply)
typeset -g PLAN_UNCHANGED=0   # 1: the plan was saved as written

# Before an editor opens: the spinner stops, Ctrl-C is the editor's again, and the lock goes so
# launchd's verify is not held off for as long as the edit takes.
runplan::release() {
  ui::spin_stop
  trap - INT TERM HUP
  lock::release
}

# runplan::basis_summary <summary.json>: the basis from one check run's summary.
runplan::basis_summary() {
  local file="${1}" name st reason fix detail actionable manual
  PLAN_STATUS=() PLAN_REASON=() PLAN_FIX=() PLAN_DETAIL=() PLAN_ACTIONABLE=() PLAN_MANUAL=() PLAN_AGE=()
  while IFS=$'\x1f' read -r name st reason actionable manual fix detail; do
    PLAN_STATUS[${name}]="${st}" PLAN_REASON[${name}]="${reason}" PLAN_FIX[${name}]="${fix}" PLAN_DETAIL[${name}]="${detail}"
    PLAN_ACTIONABLE[${name}]="${actionable}" PLAN_MANUAL[${name}]="${manual}"
  done < <(jq -r '.steps[] | [.step, .status, .reason, (.actionable|tostring), (.manual|tostring),
      (.fix // ""), ((.detail // "") | split("\n")[0])] | join("\u001f")' "${file}")
}

# runplan::basis_runs: the basis from each step's newest runs/*/<step>.result.json, however
# partial the run that wrote it (last-check.json is replaced by every --only run). No jq: a result
# the runner wrote starts {"step":…,"status":…,"reason":…, as step::result_status relies on.
runplan::basis_runs() {
  local name json prefix st reason
  local -a found
  local -i secs
  PLAN_STATUS=() PLAN_REASON=() PLAN_FIX=() PLAN_DETAIL=() PLAN_ACTIONABLE=() PLAN_MANUAL=() PLAN_AGE=()
  for name in "${STEPS[@]}"; do
    found=("${ARI_DOTFILES_STATE_DIR}"/runs/*/"${name}".result.json(N.On[1]))
    (( ${#found} )) || continue
    json="${mapfile[${found[1]}]-}"
    prefix="{\"step\":\"${name}\",\"status\":\""
    if [[ "${json}" == "${prefix}"[a-z]*\"* ]]; then
      json="${json#"${prefix}"}"; st="${json%%\"*}"
      json="${json#*\"reason\":\"}"; reason="${json%%\"*}"
    else
      IFS=$'\t' read -r st reason < <(jq -r '[.status, .reason] | @tsv' "${found[1]}" 2>/dev/null) || continue
    fi
    [[ -n "${st}" ]] || continue
    PLAN_STATUS[${name}]="${st}" PLAN_REASON[${name}]="${reason}"
    secs=0
    strftime -r -s secs '%Y%m%dT%H%M%S' "${found[1]:h:t}" 2>/dev/null || secs=0
    if (( secs )); then PLAN_AGE[${name}]="$(status::age "${secs}")"; fi
  done
}

# A step a check found nothing to apply for, but that it never checked because a need failed (or
# a setup run aborted before it), and that has an apply: init would get to it once the need is
# fixed, so the plan offers it too.
runplan::_unchecked() {
  [[ "${PLAN_STATUS[${1}]:-}" == skip && "${PLAN_REASON[${1}]:-}" == (prerequisite_*|aborted) ]] && step::is_fixable "${1}"
}

# Fills PLAN_OFFER from the basis: every actionable step, and every unchecked fixable one.
runplan::offer() {
  local name
  PLAN_OFFER=() PLAN_ANY=0
  for name in "${STEPS[@]}"; do
    (( ${+PLAN_STATUS[${name}]} )) || continue
    if [[ "${PLAN_ACTIONABLE[${name}]}" == true ]] || runplan::_unchecked "${name}"; then PLAN_OFFER+=("${name}"); fi
  done
}

# What an offered step's line says after its '#': the reason, then what the apply will do (the
# verdict's fix when it says more than 'dotfiles apply <step>', else the step's --apply).
runplan::_why() {
  local name="${1}" fix="${PLAN_FIX[${1}]:-}"
  if runplan::_unchecked "${name}"; then
    print -r -- "not checked (${PLAN_REASON[${name}]}): ${STEP_APPLY_DOC[${name}]:-apply::${name}}"
    return 0
  fi
  [[ -n "${fix}" && "${fix}" != "${CLI_NAME} apply ${name}" ]] || fix="${STEP_APPLY_DOC[${name}]:-apply::${name}}"
  print -r -- "${PLAN_REASON[${name}]}: ${fix}"
}

# runplan::write_check <verb> <apply|skip>: the plan for init or healthcheck, from PLAN_OFFER and
# the basis: the offered steps as lines with <default> as their action; then, as comments, the
# steps that need a hand (failed, errored, or warned with a fix, with nothing to apply here) and
# their fix; then every other step checked, for reference.
runplan::write_check() {
  local verb="${1}" default="${2}" name st width=0 runs
  local -a by_hand=() rest=()
  for name in "${STEPS[@]}"; do
    (( ${+PLAN_STATUS[${name}]} )) || continue
    (( ${#name} > width )) && width=${#name}
    (( ${PLAN_OFFER[(Ie)${name}]} )) && continue
    st="${PLAN_STATUS[${name}]}"
    if [[ "${st}" == (fail|error) || ( "${st}" == warn && ( -n "${PLAN_FIX[${name}]}" || "${PLAN_MANUAL[${name}]}" == true ) ) ]]; then
      by_hand+=("${name}")
    else
      rest+=("${name}")
    fi
  done
  if [[ "${verb}" == init ]]; then
    runs="Save and quit to run the 'apply' lines: each step's check, then its apply, then a
# second check, as init does; then status. An unchanged plan runs as written."
  else
    runs="Save and quit, confirm, and the 'apply' lines run in one '${CLI_NAME} apply'. The
# healthcheck applies nothing on its own: every line starts as skip."
  fi
  cat <<EOF
# ${CLI_NAME} ${verb} --edit: the steps this check found something to apply for, one per line:
#   <action> <step>  # <reason>: <what the apply does>
#   apply   run the step's apply, then check it again
#   skip    leave it as it is
# ${runs}
# Lines starting with # are comments. A step whose need failed can run only if the need is
# applied too.

EOF
  for name in "${PLAN_OFFER[@]}"; do
    printf '%-5s  %-*s  # %s\n' "${default}" "${width}" "${name}" "$(runplan::_why "${name}")"
  done
  if (( ${#by_hand} )); then
    print -r -- ""
    print -r -- "# By hand: nothing here applies these; the fix says what to do."
    for name in "${by_hand[@]}"; do
      printf '#   %-5s  %-*s  %s: %s\n' "${PLAN_STATUS[${name}]}" "${width}" "${name}" "${PLAN_REASON[${name}]}" "${PLAN_FIX[${name}]:-${PLAN_DETAIL[${name}]:-by hand}}"
    done
  fi
  if (( ${#rest} )); then
    print -r -- ""
    print -r -- "# Nothing to apply:"
    for name in "${rest[@]}"; do
      printf '#   %-5s  %-*s  %s\n' "${PLAN_STATUS[${name}]}" "${width}" "${name}" "${PLAN_REASON[${name}]}"
    done
  fi
}

# runplan::write_all <prefill..>: the plan for apply: every step in run order, `apply` for the
# prefilled ones and `skip` for the rest, each with its description, group, needs, newest result
# and its age, and check-only when it has no apply.
runplan::write_all() {
  local -a prefill=("$@") meta
  local name width=0 last action
  cat <<EOF
# ${CLI_NAME} apply --edit: every step, in run order, one per line:
#   <action> <step>  # description · group · needs · last result (age) · check-only
#   apply   run the step: its check, then its apply when the check asks for it
#   skip    leave it
# Save and quit, confirm, and the 'apply' lines run as one '${CLI_NAME} apply'. A check-only step
# runs its check alone. A need whose last result is not ok or warn must be applied too. Lines
# starting with # are comments.

EOF
  for name in "${STEPS[@]}"; do (( ${#name} > width )) && width=${#name}; done
  for name in "${STEPS[@]}"; do
    meta=("${STEP_DESC[${name}]}" "${STEP_GROUP[${name}]}")
    [[ -z "${STEP_NEEDS[${name}]}" ]] || meta+=("needs ${STEP_NEEDS[${name}]}")
    if (( ${+PLAN_STATUS[${name}]} )); then
      last="last ${PLAN_STATUS[${name}]} ${PLAN_REASON[${name}]}"
      [[ -z "${PLAN_AGE[${name}]:-}" ]] || last+=" (${PLAN_AGE[${name}]})"
      meta+=("${last}")
    else
      meta+=("never run")
    fi
    step::is_fixable "${name}" || meta+=("check-only")
    action=skip
    (( ! ${prefill[(Ie)${name}]} )) || action=apply
    printf '%-5s  %-*s  # %s\n' "${action}" "${width}" "${name}" "${(pj: · :)meta}"
  done
}

# The steps apply's plan starts as `apply` when none is named: those whose newest result failed
# or warned and that have an apply.
runplan::prefill_failing() {
  local name
  reply=()
  for name in "${STEPS[@]}"; do
    [[ "${PLAN_STATUS[${name}]:-}" == (fail|warn) ]] && step::is_fixable "${name}" && reply+=("${name}")
  done
  return 0
}

# Parses a plan into the caller's `chosen` and `planned`, and PLAN_LINE; prints one
# `line N: problem | …` per bad line on stderr and returns 1 when any is bad. A line: apply or
# skip, one step the registry knows, at most once; an apply line names a step PLAN_OFFER holds
# (unless PLAN_ANY). Then the needs: an applied step's need that is not applied too must not have
# last ended in anything but ok or warn (one never checked is the runner's gate to keep).
runplan::parse() {
  setopt localoptions extendedglob
  local file="${1}" line body action name need st
  local -a words
  local -i n=0 bad=0
  PLAN_LINE=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$(( n + 1 ))
    body="${${line%%\#*}##[[:space:]]#}"
    body="${body%%[[:space:]]#}"
    [[ -n "${body}" ]] || continue
    words=(${=body})
    action="${words[1]}" name="${words[2]:-}"
    if [[ "${action}" != (apply|skip) ]]; then
      print -u2 -r -- "line ${n}: unknown action; use apply or skip | line='${line}'"; bad=1; continue
    fi
    if (( ${#words} != 2 )); then
      print -u2 -r -- "line ${n}: expected one step after the action | line='${line}'"; bad=1; continue
    fi
    if ! step::is_known "${name}"; then
      print -u2 -r -- "line ${n}: not a step here (${CLI_NAME} steps) | step='${name}' line='${line}'"; bad=1; continue
    fi
    if (( ${planned[(Ie)${name}]} )); then
      print -u2 -r -- "line ${n}: listed twice | step='${name}'"; bad=1; continue
    fi
    if [[ "${action}" == apply ]] && (( ! PLAN_ANY )) && (( ! ${PLAN_OFFER[(Ie)${name}]} )); then
      print -u2 -r -- "line ${n}: nothing to apply for ${name} in this check (${PLAN_STATUS[${name}]:-not checked} ${PLAN_REASON[${name}]:-}) | step='${name}'"
      bad=1; continue
    fi
    planned+=("${name}")
    PLAN_LINE[${name}]="${n}"
    [[ "${action}" != apply ]] || chosen+=("${name}")
  done < "${file}"
  for name in "${chosen[@]}"; do
    for need in ${(s:,:)STEP_NEEDS[${name}]}; do
      (( ${chosen[(Ie)${need}]} )) && continue
      st="${PLAN_STATUS[${need}]:-}"
      [[ -z "${st}" || "${st}" == (ok|warn) ]] && continue
      print -u2 -r -- "line ${PLAN_LINE[${name}]}: ${name} needs ${need}, which ended ${st} ${PLAN_REASON[${need}]:-} and is not applied here; apply ${need} too, or skip ${name} | step='${name}' need='${need}'"
      bad=1
    done
  done
  return ${bad}
}

# runplan::edit <plan> <resume command>: <plan> in $EDITOR (vi when unset or missing), then
# runplan::parse. Bad lines: on a terminal, offered for another edit; else (or declined) the plan
# is kept and the error names '<resume command> <plan>'; returns 1. An editor that fails returns
# 1 too. PLAN_UNCHANGED says whether the plan was saved as written.
runplan::edit() {
  local plan="${1}" resume="${2}" editor before
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  before="${mapfile[${plan}]-}"
  PLAN_UNCHANGED=0
  while true; do
    if ! ${=editor} "${plan}"; then
      log::err "editor exited non-zero; nothing applied | editor='${editor}' plan='${plan}'"
      return 1
    fi
    chosen=() planned=()
    runplan::parse "${plan}" && break
    if [[ -t 0 && -t 1 ]] && ui::confirm "Edit the plan again?"; then continue; fi
    log::err "plan not run; fix the lines above, then | fix='${resume} ${plan}'"
    return 1
  done
  [[ "${mapfile[${plan}]-}" != "${before}" ]] || PLAN_UNCHANGED=1
  return 0
}

# On a terminal, one yes/no before the chosen steps run; off one, yes (the plan was the choice).
runplan::confirm() {
  [[ -t 0 && -t 1 ]] || return 0
  ui::confirm "${1}"
}

# The check a resumed plan is read against: last-check.json, or exit 1 when there is none.
runplan::resume_basis() {
  local verb="${1}" plan="${2}" last="${ARI_DOTFILES_STATE_DIR}/last-check.json"
  [[ -f "${plan}" ]] || usage_error "${verb} --edit: no such plan file | file='${plan}'"
  if [[ ! -f "${last}" ]]; then
    log::err "${verb} --edit: no check to read the plan against | file='${last}' fix='${CLI_NAME} ${verb} --edit'"
    exit 1
  fi
  runplan::basis_summary "${last}"
  runplan::offer
}

# --- init --edit ---

# init --edit [FILE]: the checks (parallel, as healthcheck runs them), the plan, then a setup run
# of exactly the chosen steps and status. FILE: no checks; the plan is read against last-check.json.
runplan::init() {
  local only="${1}" group="${2}" resume="${3}" plan="${ARI_DOTFILES_STATE_DIR}/init-plan.dfinit"
  local -a chosen planned
  local -i rc=0 checked=0
  if [[ -n "${resume}" ]]; then
    plan="${resume}"
    steps::load || exit 3
    runplan::resume_basis init "${plan}"
  else
    run::run check "${only}" "${group}" 0
    run::print_end 0
    run::exit_code || rc=$?
    checked=1
    runplan::release
    runplan::basis_summary "${RUN_DIR}/summary.json"
    runplan::offer
    print -r -- ""
    if (( ! ${#PLAN_OFFER} )); then
      print -r -- "init: nothing to apply"
      exit "${rc}"
    fi
    mkdir -p -- "${plan:h}"
    runplan::write_check init apply > "${plan}"
  fi
  runplan::edit "${plan}" "${CLI_NAME} init --edit" || exit 1
  runplan::_nothing init || { rm -f -- "${plan}"; exit "${rc}"; }
  lock::acquire setup
  rm -f -- "${plan}"
  (( ! checked )) || run::next_id
  run::run setup "${(j:,:)chosen}" "" 0
  run::print_end 0
  print
  cmd_status
  run::exit
}

# A plan that runs nothing says why, with the command for later, and returns 1; else 0.
runplan::_nothing() {
  local verb="${1}"
  if (( ! ${#planned} )); then
    print -r -- "${verb}: the plan has no step line; nothing applied"
  elif (( ! ${#chosen} )); then
    if [[ "${verb}" == healthcheck ]] && (( PLAN_UNCHANGED )); then print -r -- "${verb}: no change; nothing applied"
    else print -r -- "${verb}: every step skipped; nothing applied"
    fi
    print -r -- "next: ${CLI_NAME} apply ${planned[*]}"
  else
    return 0
  fi
  return 1
}

# --- apply --edit ---

# apply --edit [STEP..] | FILE: every step as a plan, the named ones (or, with none named, the
# failing ones that have an apply) as apply; confirmed on a terminal, then one setup run.
runplan::apply() {
  local resume="${1}"; shift
  local -a names=("$@") chosen planned reply
  local plan="${ARI_DOTFILES_STATE_DIR}/apply-plan.dfapply" name
  steps::load || exit 3
  for name in "${names[@]}"; do
    step::is_known "${name}" || usage_error "unknown step | step='${name}' known='${(j:,:)STEPS}'"
  done
  runplan::basis_runs
  PLAN_OFFER=() PLAN_ANY=1
  if [[ -n "${resume}" ]]; then
    [[ -f "${resume}" ]] || usage_error "apply --edit: no such plan file | file='${resume}'"
    plan="${resume}"
  else
    if (( ! ${#names} )); then runplan::prefill_failing; names=("${reply[@]}"); fi
    mkdir -p -- "${plan:h}"
    runplan::write_all "${names[@]}" > "${plan}"
  fi
  runplan::edit "${plan}" "${CLI_NAME} apply --edit" || exit 1
  if [[ -z "${resume}" ]] && (( PLAN_UNCHANGED && ! $# )); then
    rm -f -- "${plan}"
    print -r -- "apply: no change; nothing applied"
    return 0
  fi
  if (( ! ${#chosen} )); then
    rm -f -- "${plan}"
    print -r -- "apply: every step skipped; nothing applied"
    print -r -- "next: ${CLI_NAME} apply --edit"
    return 0
  fi
  if ! runplan::confirm "Apply ${chosen[*]}?"; then
    print -r -- "apply: not confirmed; nothing applied"
    print -r -- "next: ${CLI_NAME} apply --edit ${plan}"
    return 0
  fi
  rm -f -- "${plan}"
  typeset -g RUN_VERB=apply
  run::main setup "${(j:,:)chosen}" "" 0
}

# --- healthcheck --edit ---

# healthcheck --edit [FILE]: the checks and their table exactly as healthcheck prints them; then,
# when something is actionable, the plan (every line skip), a confirm, and this process becomes a
# fresh `dotfiles apply` of the chosen steps. Applying nothing exits as the healthcheck would.
# FILE: no checks; the plan is read against last-check.json.
runplan::healthcheck() {
  local only="${1}" group="${2}" resume="${3}" dry="${4}" plan="${ARI_DOTFILES_STATE_DIR}/healthcheck-plan.dfcheck" bin
  local -a chosen planned
  local -i rc=0
  if [[ -n "${resume}" ]]; then
    plan="${resume}"
    steps::load || exit 3
    runplan::resume_basis healthcheck "${plan}"
  else
    run::run check "${only}" "${group}" 0
    run::print_end 0
    run::exit_code || rc=$?
    runplan::release
    runplan::basis_summary "${RUN_DIR}/summary.json"
    runplan::offer
    print -r -- ""
    if (( ! ${#PLAN_OFFER} )); then
      print -r -- "healthcheck: nothing to apply"
      exit "${rc}"
    fi
    mkdir -p -- "${plan:h}"
    runplan::write_check healthcheck skip > "${plan}"
  fi
  runplan::edit "${plan}" "${CLI_NAME} healthcheck --edit" || exit 1
  runplan::_nothing healthcheck || { rm -f -- "${plan}"; exit "${rc}"; }
  local -a apply_args=()
  (( dry )) && apply_args+=(--dry-run)
  if ! runplan::confirm "Run ${CLI_NAME} apply ${chosen[*]}?"; then
    print -r -- "healthcheck: not confirmed; nothing applied"
    print -r -- "next: ${CLI_NAME} healthcheck --edit ${plan}"
    exit "${rc}"
  fi
  rm -f -- "${plan}"
  bin="${ARI_DOTFILES_ROOT:h}/bin/${CLI_NAME}"
  print -r -- "running: ${CLI_NAME} apply ${apply_args[*]}${apply_args:+ }${chosen[*]}"
  exec "${bin}" apply "${apply_args[@]}" "${chosen[@]}"
}
