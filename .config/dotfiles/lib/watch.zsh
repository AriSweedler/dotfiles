# dotfiles/lib/watch.zsh — which repo paths each step reads, so a pull can name the steps its
# changes affect without running a single check.
#
#   step::watches <name> <glob>..   after step::declare in steps/<name>.zsh: zsh patterns
#                                   relative to $HOME (`*` and `**` both cross `/`); a change to
#                                   a matching path means the step may need to run
#   step::watches <name> --none "<why>"
#                                   the step reads no repo file (an installed tool, the agent),
#                                   and why; the documentation rule wants one of the two forms
#
# A step's own file is always watched (steps/<name>.zsh changed → <name>); lib/, cmd/ and the
# entrypoint are the harness, live the moment they land, so they map to no step unless a step
# watches them (dotfiles_docs reads cmd/ for its rules). Lives in lib/ because every step
# subprocess sources lib/ and its step file only.

typeset -gA STEP_WATCHES=() STEP_WATCH_FILE=() STEP_WATCH_NONE=()
# The harness: a changed path here is in effect already, nothing to apply.
typeset -ga WATCH_HARNESS_GLOBS=('.config/dotfiles/lib/*' '.config/dotfiles/cmd/*' '.config/bin/dotfiles')
typeset -g WATCH_STEPS_PREFIX='.config/dotfiles/steps/'

step::watches() {
  local name="${1:?step::watches needs a step name}"; shift
  (( $# )) || { print -u2 "[ERROR] step::watches: no paths | step='${name}' want='<glob>.. or --none \"<why>\"'"; return 64; }
  STEP_WATCH_FILE[${name}]="${${funcfiletrace[1]%:*}:t:r}"
  if [[ "${1}" == --none ]]; then
    (( $# <= 2 )) || { print -u2 "[ERROR] step::watches --none takes one reason | step='${name}'"; return 64; }
    STEP_WATCH_NONE[${name}]="${2:-}"
    return 0
  fi
  STEP_WATCHES[${name}]="${STEP_WATCHES[${name}]:+${STEP_WATCHES[${name}]}"$'\n'"}${(pj:\n:)@}"
  return 0
}

# Every watch names a declared step and sits in that step's file. Exit 3 like steps::validate.
watch::validate() {
  local name rc=0
  for name in ${(k)STEP_WATCH_FILE}; do
    if (( ! ${STEPS_DECLARED[(Ie)${name}]} )); then
      print -u2 "[ERROR] watch for an undeclared step | step='${name}' file='${STEP_WATCH_FILE[${name}]}.zsh' want='step::declare ${name}'"; rc=3
    elif [[ "${STEP_WATCH_FILE[${name}]}" != "${name}" ]]; then
      print -u2 "[ERROR] watch declared in another file | step='${name}' file='${STEP_WATCH_FILE[${name}]}.zsh'"; rc=3
    fi
  done
  return "${rc}"
}

# watch::map < `git diff --name-status --no-renames` lines: what the changed paths mean, one line
# each on stdout, steps in STEPS order then any step the registry does not know (a step file
# the pull just added, when the registry was loaded from another checkout), by name:
#   step <name> <path>       <name> may need to run because <path> changed (one line per path)
#   harness <path>           the harness changed; already live
#   removed <name> <path>    a step file was deleted; nothing to apply
# Pure: reads STEPS and STEP_WATCHES, no git, no checks.
watch::map() {
  local line st p name glob
  local -i is_harness
  local -A hits=()
  local -a harness=() removed=() extra=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    st="${line%%$'\t'*}"; p="${line#*$'\t'}"
    [[ "${st}" != "${line}" ]] || { st=M; p="${line}"; }   # a bare path is a modification
    is_harness=0
    for glob in "${WATCH_HARNESS_GLOBS[@]}"; do
      if [[ "${p}" == ${~glob} ]]; then harness+=("${p}"); is_harness=1; break; fi
    done
    name="${${p#${WATCH_STEPS_PREFIX}}%.zsh}"
    if (( ! is_harness )) && [[ "${p}" == "${WATCH_STEPS_PREFIX}"*.zsh && "${name}" != */* ]]; then
      if [[ "${st}" == D* ]]; then removed+=("${name} ${p}"); continue; fi
      hits[${name}]+="${p}"$'\n'
    fi
    for name in ${(k)STEP_WATCHES}; do
      for glob in "${(@f)STEP_WATCHES[${name}]}"; do
        if [[ "${p}" == ${~glob} ]]; then hits[${name}]+="${p}"$'\n'; break; fi
      done
    done
  done
  for name in ${(ok)hits}; do (( ${STEPS[(Ie)${name}]} )) || extra+=("${name}"); done
  for name in "${STEPS[@]}" "${extra[@]}"; do
    [[ -n "${hits[${name}]:-}" ]] || continue
    for p in ${(u)${(f)hits[${name}]}}; do print -r -- "step ${name} ${p}"; done
  done
  for p in "${harness[@]}"; do print -r -- "harness ${p}"; done
  for p in "${removed[@]}"; do print -r -- "removed ${p}"; done
  return 0
}
