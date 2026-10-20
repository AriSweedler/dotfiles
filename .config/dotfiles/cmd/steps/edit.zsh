# cmd/steps/edit.zsh — `dotfiles steps edit`: open a step file in $EDITOR as a draft, check it,
# put it in place and commit it in the shared tier. Loaded by cmd/steps.zsh; defines functions only.
#
# The live file is never edited: every run sources the steps directory, and a file that does not
# load stops the healthcheck (exit 3). The draft lives in <state>/drafts/steps/NAME.zsh until it
# passes, so a failed edit resumes where it left off.

steps_edit_help() {
  cat <<EOF
${CLI_NAME} steps edit NAME [--new] [--no-commit]

Opens steps/NAME.zsh in \$EDITOR, vi when unset, as a draft. On save the draft is checked: zsh -n;
then, in a fresh zsh -f with the kernel and every other step file, the registry loads with the
draft in place of the file (steps::load, watch::validate), the draft declares NAME, prints nothing
when sourced, and meets the documentation rule: line 1 '# step NAME — <summary>', a non-empty
--desc, --apply "<what the apply changes>" exactly when apply::NAME exists, and step::watches NAME
<glob>.. or step::watches NAME --none "<why>". A draft that passes replaces the file and is
committed in the shared tier; one that does not is reported and kept for the next 'steps edit
NAME' (on a terminal, offered for another edit).

  --new        create steps/NAME.zsh from a template (a check and an apply; a check-only step
               deletes the apply and its --apply)
  --no-commit  put it in place, leave it uncommitted

Exit 0 saved (or no change); 1 the draft did not pass, the editor failed or the commit was
refused; 64 usage.
EOF
}

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
  local name="" new=0 commit=1 file draft editor verb has_apply=""
  while (( $# )); do
    case "${1}" in
      -h|--help) steps_edit_help; return 0 ;;
      --new) new=1 ;;
      --no-commit) commit=0 ;;
      -*) usage_error "steps edit: unknown flag | flag='${1}'" ;;
      *) [[ -z "${name}" ]] || usage_error "steps edit takes one NAME | args='${name} ${1}'"; name="${1}" ;;
    esac
    shift
  done
  [[ -n "${name}" ]] || usage_error "steps edit needs a NAME | see='${CLI_NAME} steps'"
  [[ "${name}" == [a-z][a-z0-9_]# ]] || usage_error "steps edit: a step name is lowercase letters, digits and _ | name='${name}'"
  file="${ARI_DOTFILES_STEPS}/${name}.zsh"
  if (( new )); then
    [[ ! -e "${file}" ]] || { log::err "step exists; edit it without --new | file='${file}'"; return 1; }
  elif [[ ! -f "${file}" ]]; then
    log::err "no such step; --new creates one | name='${name}' fix='${CLI_NAME} steps edit ${name} --new'"
    return 1
  fi

  draft="${ARI_DOTFILES_STATE_DIR}/drafts/steps/${name}.zsh"
  mkdir -p -- "${draft:h}" || return 1
  if [[ -f "${draft}" ]]; then
    log::info "resuming the draft a failed edit left | draft='${draft}'"
  elif (( new )); then
    steps_edit_template "${name}" > "${draft}"
  else
    cp -- "${file}" "${draft}"
  fi
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  local -i tty=0
  [[ -t 0 && -t 1 ]] && tty=1
  while true; do
    if ! ${=editor} "${draft}"; then
      log::err "editor exited non-zero; draft kept, nothing changed | editor='${editor}' draft='${draft}'"
      return 1
    fi
    if (( new )) && cmp -s -- "${draft}" <(steps_edit_template "${name}"); then
      rm -f -- "${draft}"
      print -r -- "steps: no change; nothing created | step=${name}"
      return 0
    fi
    if (( ! new )) && cmp -s -- "${draft}" "${file}"; then
      rm -f -- "${draft}"
      print -r -- "steps: no change | step=${name} file=$(ui::paths "${file}")"
      return 0
    fi
    has_apply="$(steps_edit_check "${draft}" "${name}")" && break
    if (( tty )) && ui::confirm "Edit ${name} again?"; then continue; fi
    log::err "step not saved; draft kept | draft='${draft}' fix='${CLI_NAME} steps edit ${name}${${new:#0}:+ --new}'"
    return 1
  done

  # In place: written beside the live file and renamed over it, so a run never sources half a file.
  cp -- "${draft}" "${file}.edit.$$" && chmod 644 "${file}.edit.$$" && mv -f -- "${file}.edit.$$" "${file}" || {
    rm -f -- "${file}.edit.$$"
    log::err "could not put the step in place; draft kept | file='${file}' draft='${draft}'"
    return 1
  }
  rm -f -- "${draft}"
  verb=edit; (( new )) && verb=add
  print -r -- "step ${name}: saved | file=$(ui::paths "${file}")"
  if (( commit )); then
    tier::commit shared "${CLI_NAME}: ${verb} step ${name} (shared)" "${file}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${file}")"
  fi
  print -r -- "next: ${CLI_NAME} healthcheck --only ${name}"
  [[ "${has_apply}" != apply ]] || print -r -- "next: ${CLI_NAME} apply ${name}"
}
