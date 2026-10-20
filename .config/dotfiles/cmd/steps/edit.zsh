# cmd/steps/edit.zsh — `dotfiles steps edit`: open a step file in $EDITOR as a draft, check it,
# put it in place and commit it in the shared tier. Loaded by cmd/steps.zsh; defines functions only.
#
# The live file is never edited: every run sources the steps directory, and a file that does not
# load stops the healthcheck (exit 3). The draft (edit::draft, under <state>/drafts) is kept until
# it passes, so a failed edit resumes where it left off.

# What --new starts from. Its empty summary, --desc, --apply and --none reason are not
# documentation, so a template edited elsewhere but not there does not pass.
steps_edit_template() {
  local name="${1}"
  cat <<EOF
# step ${name} —
# What ${name} makes true on this machine, what its check reads, and what its apply changes.
step::declare ${name} --group tools \\
  --desc "" \\
  --apply ""
# The repo paths (relative to HOME) whose change means ${name} may need to run, or --none "<why>".
step::watches ${name} --none ""

check::${name}() {
  verdict fail todo -d "check::${name} is a template"
}

# A check-only step: delete apply::${name} and its --apply.
apply::${name}() {
  run_mut true
}
EOF
}

# steps_edit_check <draft> <name>: every problem with the draft on stderr, one per line, and 1
# when there is any; on a pass prints 'apply' when the step defines apply::<name>.
steps_edit_check() {
  local draft="${1}" name="${2}" out dir f err rc=0
  if ! out="$(zsh -n "${draft}" 2>&1)"; then
    print -u2 -r -- "syntax: ${${(f)out}[1]}"
    return 1
  fi
  # The steps directory as it would be with the draft in place: links to every other step file.
  dir="$(mktemp -d "${TMPDIR:-/tmp}/steps-edit.XXXXXX")" || return 1
  err="${dir}.err"
  for f in "${ARI_DOTFILES_STEPS}"/*.zsh(N); do
    [[ "${f:t}" == "${name}.zsh" ]] || ln -s -- "${f}" "${dir}/${f:t}"
  done
  ln -s -- "${draft}" "${dir}/${name}.zsh"
  out="$(zsh -f -c '
    for f in "$1"/*.zsh(N); do source "$f"; done
    steps::load "$2" 1>&2 || exit 3   # a step file prints nothing when sourced: any output is a problem
    watch::validate || exit 3
    (( ${STEPS_DECLARED[(Ie)$3]} )) || { print -u2 -r -- "declares no step $3; want step::declare $3"; exit 3; }
    if [[ -n "${STEP_UNDOCUMENTED[$3]:-}" ]]; then print -u2 -r -- "undocumented: ${STEP_UNDOCUMENTED[$3]}"; exit 1; fi
    if (( ${+functions[apply::$3]} )); then print -r -- apply; fi
    exit 0' steps-edit "${ARI_DOTFILES_LIB}" "${dir}" "${name}" 2> "${err}")" || rc=$?
  rm -f -- "${dir}"/*.zsh(N@)
  rmdir -- "${dir}" 2>/dev/null || true
  if (( rc != 0 )) || [[ -s "${err}" ]]; then
    if [[ -s "${err}" ]]; then cat -- "${err}" >&2
    else print -u2 -r -- "the registry did not load with the draft (exit ${rc})"
    fi
    rm -f -- "${err}"
    return 1
  fi
  rm -f -- "${err}"
  print -r -- "${out}"
}

steps_edit() {
  setopt localoptions extendedglob
  local -A opts; local -a args
  verb::parse steps "$@"
  local name="${args[1]:-}" file draft verb
  local -i new=${+opts[--new]} rc=0
  (( ${#args} <= 1 )) || usage_error "steps edit takes one NAME | args='${args[*]}'"
  [[ -n "${name}" ]] || usage_error "steps edit needs a NAME | see='${CLI_NAME} steps'"
  [[ "${name}" == [a-z][a-z0-9_]# ]] || usage_error "steps edit: a step name is lowercase letters, digits and _ | name='${name}'"
  file="${ARI_DOTFILES_STEPS}/${name}.zsh"
  if (( new )); then
    [[ ! -e "${file}" ]] || { log::err "step exists; edit it without --new | file='${file}'"; return 1; }
  elif [[ ! -f "${file}" ]]; then
    log::err "no such step; --new creates one | name='${name}' fix='${CLI_NAME} steps edit ${name} --new'"
    return 1
  fi

  STEPS_EDIT_NAME="${name}" STEPS_EDIT_APPLY=""
  edit::draft "${file}" "${ARI_DOTFILES_STATE_DIR}/drafts" steps::_edit_template || return 1
  draft="${REPLY}"
  edit::session "${draft}" --check steps::_edit_check --what "${name}" ${${EDIT_RESUMED:#0}:+--changed} \
    --resume "${CLI_NAME} steps edit ${name}${${new:#0}:+ --new}" || rc=$?
  # A resumed draft edited back to the live file is no change either.
  if (( rc == 2 )) || { (( rc == 0 && ! new )) && edit::same "${draft}" "${file}"; }; then
    rm -f -- "${draft}"
    if (( new )); then print -r -- "steps: no change; nothing created | step=${name}"
    else print -r -- "steps: no change | step=${name} file=$(ui::paths "${file}")"; fi
    return 0
  fi
  (( rc == 0 )) || return 1
  edit::install "${draft}" "${file}" 644 || return 1
  verb=edit; (( new )) && verb=add
  print -r -- "step ${name}: saved | file=$(ui::paths "${file}")"
  if (( ${+opts[--no-commit]} )); then
    print -r -- "not committed | file=$(ui::paths "${file}")"
  else
    tier::commit shared "${CLI_NAME}: ${verb} step ${name} (shared)" "${file}" || return 1
  fi
  print -r -- "next: ${CLI_NAME} healthcheck --only ${name}"
  [[ "${STEPS_EDIT_APPLY}" != apply ]] || print -r -- "next: ${CLI_NAME} apply ${name}"
}

steps::_edit_template() { steps_edit_template "${STEPS_EDIT_NAME}"; }
# The check edit::session runs; on a pass, STEPS_EDIT_APPLY says whether the step has an apply.
steps::_edit_check() {
  local out
  out="$(steps_edit_check "${1}" "${STEPS_EDIT_NAME}")" || return 1
  STEPS_EDIT_APPLY="${out}"
}
