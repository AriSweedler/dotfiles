#!/usr/bin/env zsh
# Canonical dry-run gate for skill zsh scripts that mutate anything. Source it right after
# logging.zsh; do not execute. Convention: /ari-skill-shellscripts § Dry run.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
#   resolve_dry_run "${execute}" "${dry_run}"            # after the parse loop; exports DRY_RUN=1|0
#   run_mut gh pr edit "${pr}" --add-label ready         # logs `would run` in a dry run
#   url="$(run_mut --dry-out '<new-pr-url>' gh pr create …)"; (( MUT_COUNT += 1 ))
#   print -r -- "${body}" | write_mut "${file}"          # never `run_mut … > file`
#   report_dry_run "${SCRIPT_PATH}" "${args[@]}"         # last: the exact rerun, or nothing to change
#
# SCRIPT_PATH is "${0:a}" taken at the top level (inside a function $0 is its name), and args the
# original "$@". A run_mut inside $(…) counts in the subshell only, so the caller adds one.
#
# The dotfiles kernel (~/.config/dotfiles/lib/run.zsh) has its own is_dry_run and run_mut on
# ARI_DOTFILES_DRY_RUN, where unset means act. Never source both into one process: this lib
# refuses to load over them.

if ! typeset -f log::info >/dev/null; then
  print -u2 "[ERROR] dry_run.zsh needs logging.zsh sourced first | lib='${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh'"
  return 1
fi
[[ -n "${_ARI_DRY_RUN_ZSH:-}" ]] && return 0
if typeset -f run_mut >/dev/null || typeset -f is_dry_run >/dev/null; then
  log::err "dry_run.zsh refuses to load over an existing run_mut or is_dry_run | fix='delete the local definition; this lib is the one gate'"
  return 1
fi
readonly _ARI_DRY_RUN_ZSH=1
typeset -gi _DRY_RUN_RESOLVED=0 MUT_COUNT=0

#######################################
# Decide whether this run acts and export the answer as DRY_RUN (1 = dry run, 0 = act), so a
# child script inherits it. Acts only when --execute is on this command line, --dry-run is not,
# and no parent exported a DRY_RUN other than empty or 0.
# Globals: DRY_RUN (read as inherited, then exported), _DRY_RUN_RESOLVED (set)
# Arguments: $1 - "true" when --execute was given; $2 - "true" when --dry-run was given
# Returns: 1 when DRY_RUN is read-only
#######################################
resolve_dry_run() {
  local execute="${1}" dry_run="${2}" inherited="${DRY_RUN:-}"
  if [[ "${(t)DRY_RUN:-}" == *readonly* ]]; then
    log::err "DRY_RUN is read-only; the gate cannot set it | DRY_RUN='${inherited}' fix='never declare DRY_RUN in a script'"
    return 1
  fi
  _DRY_RUN_RESOLVED=1
  if [[ "${dry_run}" == "true" ]]; then
    export DRY_RUN=1
    if [[ "${execute}" == "true" ]]; then
      log::warn "Dry run: --dry-run overrides --execute; nothing will change | fix='drop --dry-run'"
      return 0
    fi
    log::info "Dry run: --dry-run given; nothing will change"
    return 0
  fi
  if [[ -n "${inherited}" && "${inherited}" != "0" ]]; then
    export DRY_RUN=1
    if [[ "${execute}" == "true" ]]; then
      log::warn "Dry run: inherited DRY_RUN overrides --execute; nothing will change | inherited='${inherited}' fix='unset DRY_RUN'"
      return 0
    fi
    log::info "Dry run: inherited from the parent; nothing will change | inherited='${inherited}'"
    return 0
  fi
  export DRY_RUN=1
  if [[ "${execute}" != "true" ]]; then
    log::info "Dry run: the default; nothing will change | rerun='--execute'"
    return 0
  fi
  export DRY_RUN=0
  log::info "Executing: --execute given"
}

#######################################
# Whether this run is a dry run. It is one unless this process resolved to act: an inherited
# DRY_RUN=0 alone never makes a script act.
# Globals: DRY_RUN, _DRY_RUN_RESOLVED
# Arguments: None
#######################################
is_dry_run() {
  (( _DRY_RUN_RESOLVED )) && [[ "${DRY_RUN:-1}" == "0" ]] && return 1
  return 0
}

#######################################
# Run one mutating command, or log it in a dry run. A redirection on the call applies to run_mut
# itself and truncates its target even in a dry run: write files with write_mut instead.
# Globals: MUT_COUNT (incremented), _DRY_RUN_RESOLVED
# Arguments: [--dry-out VALUE] - printed on stdout in place of the command's output in a dry run;
#            then the command and its args
# Returns: 0 in a dry run; the command's code otherwise
#######################################
run_mut() {
  local dry_out=""
  if [[ "${1:-}" == "--dry-out" ]]; then
    dry_out="${2:?run_mut --dry-out requires a value}"
    shift 2
  fi
  (( MUT_COUNT += 1 ))
  if (( ! _DRY_RUN_RESOLVED )); then
    log::err "run_mut before resolve_dry_run; treating as a dry run | cmd=${(j: :)${(q-)@}}"
  fi
  if is_dry_run; then
    log::info "would run | cmd=${(j: :)${(q-)@}}"
    [[ -n "${dry_out}" ]] && print -r -- "${dry_out}"
    return 0
  fi
  run_cmd "$@"
}

#######################################
# Write stdin to a file, or in a dry run drain stdin and log the write it would make.
# Globals: MUT_COUNT (incremented)
# Arguments: $1 - file; $2 - "--append" to append (default: replace)
#######################################
write_mut() {
  local file="${1:?write_mut requires a file}" mode="${2:-replace}" bytes
  (( MUT_COUNT += 1 ))
  if is_dry_run; then
    bytes="$(wc -c | tr -d ' ')"
    log::info "would write | file='${file}' bytes='${bytes}' mode='${mode#--}'"
    return 0
  fi
  log::info "writing | file='${file}' mode='${mode#--}'"
  if [[ "${mode}" == "--append" ]]; then
    cat >> "${file}"
    return
  fi
  cat > "${file}"
}

#######################################
# The closing log line of a mutating script: the exact command that acts (in the $HOME form, with
# --dry-run dropped and --execute added), or that there was nothing to change.
# Globals: MUT_COUNT, DRY_RUN (via is_dry_run)
# Arguments: $1 - the script's absolute path (${0:A}); $2.. - its original arguments
#######################################
report_dry_run() {
  local script="${1}"; shift
  local -a args=("${@:#--dry-run}")
  args=("${(@)args:#--execute}")
  if (( MUT_COUNT == 0 )); then
    log::info "Nothing to change | changes='0'"
    return 0
  fi
  if ! is_dry_run; then
    log::info "Executed | changes='${MUT_COUNT}'"
    return 0
  fi
  log::info "Dry run; nothing changed | changes='${MUT_COUNT}' rerun='zsh ${script/#${HOME}/\$HOME} ${(j: :)${(q-)args[@]}} --execute'"
}
