# dotfiles/lib/cache.zsh — a check's verdict, reused while nothing it reads has changed.
#
#   cache::check <fn> <input>..   in a check::<name> body: runs <fn> and prints its verdict, or
#                                 prints the stored one when the fingerprint of every <input>
#                                 (a path: file, dir, or absent) is what it was when stored
#
# The fingerprint is each input's mtime, size, inode and mode (zstat, no fork), plus the step's
# own file, this file, HOME and PATH (stored under <state>/cache/<step>.*), plus any file the caller lists in CACHE_EXTRA
# and the value of every variable it names in CACHE_ENV (a seam that changes what the check reads). A hit
# prints the stored verdict with `cached: true | fp='<sha>' at='<ts>'` as the detail's last
# line; the status, reason and items are the stored run's. Files the check wrote into RUN_DIR
# are stored beside it and restored on a hit, so a run's summary is whole.
#
# Never stored: an error verdict; a run where an input's mtime is this second or the last
# (a same-second, same-size rewrite would look unchanged: git's racy-index rule). Never used:
# in setup mode (an apply changes the machine, and its recheck must look), and when
# ARI_DOTFILES_NO_CACHE=1. A directory input changes when an entry is added or removed, not
# when a file inside it is rewritten: list such files as inputs too.
zmodload -F zsh/stat b:zstat
zmodload zsh/datetime
zmodload zsh/mapfile

typeset -ga CACHE_EXTRA=() CACHE_ENV=()

# Sets REPLY to the fingerprint of the given paths: one 'path m s i p' line each, '-' when absent.
# CACHE_RACY is set to 1 when any of them changed within the last two seconds.
cache::fingerprint() {
  local p
  local -A st
  local -a lines=()
  CACHE_RACY=0
  for p in "$@"; do
    if zstat -H st -- "${p}" 2>/dev/null; then
      lines+=("${p} ${st[mtime]} ${st[size]} ${st[inode]} ${st[mode]}")
      (( st[mtime] < EPOCHSECONDS - 1 )) || CACHE_RACY=1
    else
      lines+=("${p} -")
    fi
  done
  REPLY="${(F)lines}"
}

cache::enabled() {
  [[ "${ARI_DOTFILES_NO_CACHE:-0}" != 1 && "${ARI_DOTFILES_MODE:-check}" != setup && -n "${STEP:-}" ]]
}

# The files of RUN_DIR the runner owns, for this step or another (checks of a group run side by
# side, so another step's files can appear meanwhile); the rest a check wrote is its output.
cache::_is_runner_file() {
  [[ "${1}" == (*.log|*.check.json|*.check.<->.json|*.recheck.json|*.result.json|.*|summary.json) ]]
}

# reply+=: each dir and everything under it, for an input that is a tree (a file rewritten in
# place changes only its own mtime, so every file is listed).
cache::tree() {
  local d
  for d in "$@"; do reply+=("${d}" "${d}"/**/*(ND)); done
}

cache::check() {
  local fn="${1:?cache::check needs a function}"; shift
  local REPLY CACHE_RACY fp
  local base="${ARI_DOTFILES_STATE_DIR}/cache/${STEP}"
  cache::fingerprint "$@" "${ARI_DOTFILES_STEPS}/${STEP}.zsh" "${ARI_DOTFILES_LIB}/cache.zsh" "${CACHE_EXTRA[@]}"
  fp="HOME=${HOME}"$'\n'"PATH=${PATH}"$'\n'"${REPLY}"
  local v
  for v in "${CACHE_ENV[@]}"; do fp+=$'\n'"env ${v}=${(P)v-<unset>}"; done
  if cache::enabled && [[ -r "${base}.fp" && -r "${base}.verdict" && "${mapfile[${base}.fp]}" == "${fp}" ]]; then
    local f
    for f in "${base}.files/"*(N.); do mapfile[${RUN_DIR}/${f:t}]="${mapfile[${f}]}"; done
    print -r -- "${mapfile[${base}.verdict]%$'\n'}"
    log::info "cache hit | step='${STEP}'"
    return 0
  fi
  local racy="${CACHE_RACY}"
  local -a before=("${RUN_DIR:-/nonexistent}"/*(N.:t))
  local out
  out="$("${fn}")" || return
  print -r -- "${out}"
  [[ "${ARI_DOTFILES_NO_CACHE:-0}" != 1 && -n "${STEP:-}" ]] || return 0
  if (( racy )); then log::info "cache not stored: an input changed just now | step='${STEP}'"; return 0; fi
  local verdict_status
  verdict_status="$(jq -r '.status' <<< "${out}" 2>/dev/null)" || return 0
  [[ "${verdict_status}" == (ok|warn|fail|skip) ]] || return 0
  local sha ts marked f
  sha="$(print -rn -- "${fp}" | shasum -a 256)"; sha="${sha[1,12]}"
  strftime -s ts '%Y-%m-%dT%H:%M:%S' "${EPOCHSECONDS}"
  marked="$(jq -c --arg m "cached: true | fp='${sha}' at='${ts}'" \
    '.detail = (if (.detail // "") == "" then $m else .detail + "\n" + $m end)' <<< "${out}")" || return 0
  mkdir -p "${base}.files" || return 0
  for f in "${base}.files/"*(N.); do rm -f -- "${f}"; done
  if [[ -n "${RUN_DIR:-}" ]]; then
    for f in "${RUN_DIR}"/*(N.:t); do
      (( ${before[(Ie)${f}]} )) && continue
      cache::_is_runner_file "${f}" && continue
      mapfile[${base}.files/${f}]="${mapfile[${RUN_DIR}/${f}]}"
    done
  fi
  mapfile[${base}.verdict]="${marked}"$'\n'
  mapfile[${base}.fp.tmp]="${fp}"
  mv -f -- "${base}.fp.tmp" "${base}.fp"
  return 0
}

# --- Machine inputs, for the steps that read Homebrew's state ---

# The prefix of the brew the checks run: <prefix>/bin/brew beside <prefix>/Cellar. Sets REPLY;
# 1 when the brew in use has no Cellar beside it (a wrapper, a test shim): its state is not
# on disk where the cache can see it, so the caller runs uncached.
cache::brew_prefix() {
  REPLY="${ARI_DOTFILES_BREW:h:h}"
  [[ -n "${ARI_DOTFILES_BREW}" && -d "${REPLY}/Cellar" ]]
}
