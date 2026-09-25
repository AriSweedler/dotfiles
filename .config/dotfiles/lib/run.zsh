# dotfiles/lib/run.zsh — running things: the dry-run gate, timing, prerequisites, watchdogs,
# libraries on demand, and the small text helpers every module reaches for.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

# The one dry-run predicate. DOTFILES_DRY_RUN is exported by --dry-run, so it crosses into every
# step subprocess and every tool the harness execs.
is_dry_run() {
  case "${DOTFILES_DRY_RUN:-0}" in 0|false|no|"") return 1 ;; esac
  return 0
}

# Run a state-changing command, or print it under --dry-run. Every mutation goes through here so
# dry-run has no second code path to disagree with; `runner=run_cmd_cap run_mut …` also logs stdout.
run_mut() {
  if is_dry_run; then log::info "dry-run, would run | cmd='${*}'"; return 0; fi
  "${runner:-run_cmd}" "${@}"
}
run_cmd_mutating() { run_mut "${@}"; }   # the brew model's name for it

# Seconds since a start taken from EPOCHREALTIME, two decimals.
elapsed() { printf '%.2f' $(( EPOCHREALTIME - ${1} )); }

# Run a labelled command and time it: every one under --timing, otherwise only one slower than
# DOTFILES_SLOW_STEP, so a slow run names its culprit. A network round trip sets its own bar:
# `slow=5 timed pull …`.
timed() {
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
step() { timed "${@}"; }

check_prerequisites() {
  local -a missing=()
  local cmd
  for cmd in "${@}"; do command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}"); done
  if (( ${#missing} > 0 )); then log::err "Missing required commands | missing='${(j:, :)missing}'"; return 1; fi
}

# Source a library once per process, by path (with or without .zsh). How a step or verb pulls
# in the domain library it needs without every process parsing all of them.
need_lib() {
  local file="${1%.zsh}.zsh" key
  key="need_lib_${file//[^A-Za-z0-9]/_}"
  (( ${+parameters[${key}]} )) && return 0
  if [[ ! -r "${file}" ]]; then log::err "missing lib | path='${file}'"; return 3; fi
  source "${file}" || return 3
  typeset -g "${key}=1"
}

# --- Watchdog ---

# Kills a process tree deepest-first, so a brew two forks down (a function run inside $(...))
# dies with the check instead of surviving it and holding brew's lock.
kill_tree() {
  local sig="${1}" pid="${2}" child
  local -a children=(${(f)"$(pgrep -P "${pid}" 2>/dev/null || true)"})
  for child in "${children[@]}"; do
    kill_tree "${sig}" "${child}"
  done
  kill "-${sig}" "${pid}" 2>/dev/null || true
}

# with_timeout <secs> <cmd…>: TERM to the child's whole tree after secs, KILL 5 s later; reaps its
# own sleeper so runs and tests leave no stragglers. 0 = no timeout. Returns the command's rc
# (143/137 when killed).
with_timeout() {
  local secs="${1}"; shift
  if (( secs == 0 )); then "$@"; return; fi
  "$@" & local pid=$!
  ( sleep "${secs}"; kill_tree TERM "${pid}"; sleep 5; kill_tree KILL "${pid}" ) & local wd=$!
  local rc=0; wait "${pid}" || rc=$?
  pkill -P "${wd}" 2>/dev/null; kill "${wd}" 2>/dev/null; wait "${wd}" 2>/dev/null || true
  return "${rc}"
}

# --- Text helpers ---
plural() {
  local n="${1}" one="${2}" many="${3}"
  if (( n == 1 )); then print -r -- "${n} ${one}"; else print -r -- "${n} ${many}"; fi
}
tail_lines() {
  local file="${1}" n="${2:-10}"
  if [[ -f "${file}" ]]; then
    tail -n "${n}" "${file}"
  fi
}
