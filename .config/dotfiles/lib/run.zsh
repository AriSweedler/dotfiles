# dotfiles/lib/run.zsh — running a step: dry-run gating, timing, prerequisites.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

# Run a state-changing command, or print it under --dry-run; `runner=run_cmd_cap run_mut …` also logs its stdout.
run_mut() {
  if [[ "${DRY_RUN}" == true ]]; then log::info "dry-run, would run | cmd='${*}'"; return 0; fi
  "${runner:-run_cmd}" "${@}"
}
# Seconds since a start taken from EPOCHREALTIME, two decimals.
elapsed() { printf '%.2f' $(( EPOCHREALTIME - ${1} )); }

# Run a step (label, then the command) and time it: every step under --timing, otherwise
# only one slower than DOTFILES_SLOW_STEP, so a slow run names its culprit. A step that is
# a network round trip sets its own bar: `slow=5 step pull …`.
step() {
  local label="${1}"; shift
  local start="${EPOCHREALTIME}" rc=0 took threshold="${slow:-${DOTFILES_SLOW_STEP}}"
  "${@}" || rc=$?
  took="$(elapsed "${start}")"
  if [[ "${TIMING}" == true ]]; then
    log::info "step | name='${label}' took='${took}s'"
  elif (( took >= threshold )); then
    log::warn "slow step | name='${label}' took='${took}s' threshold='${threshold}s'"
  fi
  return "${rc}"
}

check_prerequisites() {
  local -a missing=()
  local cmd
  for cmd in "${@}"; do command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}"); done
  if (( ${#missing} > 0 )); then log::err "Missing required commands | missing='${(j:, :)missing}'"; return 1; fi
}
