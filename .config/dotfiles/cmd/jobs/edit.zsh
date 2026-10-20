# cmd/jobs/edit.zsh — `dotfiles jobs edit`: open a job plugin or dep in $EDITOR as a draft, check
# it, put it in place and commit it in its tier. Loaded by cmd/jobs.zsh; defines functions only.
#
# The live file is never edited: the resident agent rediscovers plugins and rereads their headers
# on every tick, and a new plugin with a `# cron:` line is due at once. The draft lives in
# JOBS_STATE_DIR/drafts until it passes, so a failed edit resumes where it left off.

jobs_edit_help() {
  cat <<EOF
${CLI_NAME} jobs edit NAME [--new] [--local|--global] [--dep] [--no-commit] [--no-push]

Opens the job plugin NAME (or, with --dep, the dep NAME) in \$EDITOR, vi when unset, as a draft.
On save the draft is checked: its interpreter's syntax check (-n) for zsh, bash and sh; the
'# triggers:' words (unlock, load); each '# cron:' line's five fields; '# timeout:' a number;
each '# deps:' name a dep that exists; and the documentation rule, a line saying what it does
and, for a plugin, a '# triggers:' or '# cron:' line. A draft that passes replaces the file,
executable, and is committed in its tier; one that does not is reported and kept for the next
'jobs edit NAME' (on a terminal, offered for another edit). The agent is never reloaded: it
reads plugins on its next tick.

  --new        create NAME from a template (in the local tier unless --global)
  --local      with --new: ~/.local/share/dotfiles/{jobs,deps} (git ldf; committed and pushed)
  --global     with --new: ~/.config/dotfiles/{jobs,deps} (git df; committed, never pushed)
  --dep        a dep, not a plugin
  --no-commit  put it in place, leave it uncommitted
  --no-push    skip the local tier's push

Exit 0 saved (or no change); 1 the draft did not pass, the editor failed or the commit was
refused; 64 usage.
EOF
}

# jobs_edit_template <plugin|dep> <name>: what --new starts from. Its TODO line is not
# documentation, so an unedited template does not pass.
jobs_edit_template() {
  print -r -- '#!/usr/bin/env zsh'
  if [[ "${1}" == dep ]]; then
    print -r -- "# TODO: what ${2} provides; print NAME=VALUE lines on stdout, chatter on stderr."
  else
    print -r -- '# triggers: unlock load'
    print -r -- "# TODO: what ${2} does. Print a one-line summary last; the framework posts the banner."
  fi
  print -r -- 'set -euo pipefail'
}

# jobs_edit_check <file> <plugin|dep>: every problem with the draft on stderr, one per line;
# 1 when there is any.
jobs_edit_check() {
  setopt localoptions extendedglob
  local file="${1}" kind="${2}" shebang interp line word out
  local -a problems=() fields reply
  shebang="$(head -n 1 -- "${file}")"
  interp="${${shebang#\#!}%% *}"
  [[ "${interp:t}" == env ]] && interp="${${(z)shebang}[2]}"
  case "${interp:t}" in
    zsh|bash|sh)
      if ! out="$("${interp:t}" -n "${file}" 2>&1)"; then problems+=("syntax: ${${(f)out}[1]}"); fi ;;
    *) [[ "${shebang}" == '#!'* ]] || problems+=("no '#!' line: the framework runs the file itself") ;;
  esac
  if [[ "${kind}" == plugin ]]; then
    for word in $(jobs_triggers "${file}"); do
      [[ "${word}" == (unlock|load) ]] || problems+=("'# triggers:' takes unlock and load, not '${word}'")
    done
    while IFS= read -r line; do
      fields=(${=line})
      jobs_is_cron_valid "${fields[@]}" || problems+=("'# cron: ${line}' is not five valid fields")
    done < <(jobs_crons "${file}")
    line="$(grep -m1 -E '^# timeout:' "${file}" 2>/dev/null || true)"
    line="${${line#\# timeout:}##[[:space:]]#}"
    [[ -z "${line}" || "${line}" == <-> ]] || problems+=("'# timeout:' takes seconds, not '${line}'")
    deps_discover
    for word in $(jobs_deps "${file}"); do
      [[ -n "${DEP_PATH[${word}]:-}" ]] || problems+=("'# deps:' names '${word}', which is no dep (dotfiles jobs list)")
    done
  fi
  jobs_doc_problems "${file}" "${kind}"
  problems+=("${reply[@]/#/undocumented: }")
  (( ${#problems} == 0 )) && return 0
  print -u2 -rl -- "${problems[@]}"
  return 1
}

jobs_edit() {
  local name="" kind=plugin tier="" new=0 commit=1 file="" root editor draft rel verb
  while (( $# )); do
    case "${1}" in
      -h|--help) jobs_edit_help; return 0 ;;
      --new) new=1 ;;
      --local) tier=ldf ;;
      --global) tier=df ;;
      --dep) kind=dep ;;
      --no-commit) commit=0 ;;
      --no-push) export ARI_DOTFILES_NO_PUSH=1 ;;
      -*) usage_error "jobs edit: unknown flag | flag='${1}'" ;;
      *) [[ -z "${name}" ]] || usage_error "jobs edit takes one NAME | args='${name} ${1}'"; name="${1}" ;;
    esac
    shift
  done
  [[ -n "${name}" ]] || usage_error "jobs edit needs a NAME | see='${CLI_NAME} jobs list'"
  [[ "${name}" != */* && "${name}" != .* && "${name}" != README.md ]] || usage_error "jobs edit: not a plugin name | name='${name}'"
  local -a roots
  if [[ "${kind}" == dep ]]; then roots=("${DEPS_ROOT_DF}" "${DEPS_ROOT_LDF}"); else roots=("${JOBS_ROOT_DF}" "${JOBS_ROOT_LDF}"); fi
  # An existing file, executable or not (a plugin turned off with chmod -x is still one to edit).
  local -a found=("${roots[1]}/${name}"(N.) "${roots[2]}/${name}"(N.))
  if (( new )); then
    (( ${#found} == 0 )) || { log::err "${kind} exists; edit it without --new | file='${found[1]}'"; return 1; }
    [[ -n "${tier}" ]] || tier=ldf
    if [[ "${tier}" == df ]]; then root="${roots[1]}"; else root="${roots[2]}"; fi
    file="${root}/${name}"
  else
    [[ -z "${tier}" ]] || usage_error "jobs edit: --local and --global choose the tier of a --new ${kind} only"
    if (( ${#found} == 0 )); then
      log::err "no such ${kind}; --new creates one | name='${name}' fix='${CLI_NAME} jobs edit ${name}${${kind:#plugin}:+ --dep} --new'"
      return 1
    fi
    if (( ${#found} > 1 )); then
      log::err "${kind} in both tiers; remove one first | name='${name}' files='${(j:, :)found}'"
      return 1
    fi
    file="${found[1]}"
    tier=df; [[ "${file}" == "${roots[2]}/"* ]] && tier=ldf
  fi

  draft="${JOBS_STATE_DIR}/drafts/${kind}-${name}"
  mkdir -p -- "${draft:h}" || return 1
  if [[ -f "${draft}" ]]; then
    log::info "resuming the draft a failed edit left | draft='${draft}'"
  elif (( new )); then
    jobs_edit_template "${kind}" "${name}" > "${draft}"
  else
    cp -- "${file}" "${draft}"
  fi
  local before; before="$(mktemp "${TMPDIR:-/tmp}/jobs-edit.XXXXXX")" || return 1
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  local -i tty=0
  [[ -t 0 && -t 1 ]] && tty=1
  while true; do
    cp -- "${draft}" "${before}"
    if ! ${=editor} "${draft}"; then
      rm -f -- "${before}"
      log::err "editor exited non-zero; draft kept, nothing changed | editor='${editor}' draft='${draft}'"
      return 1
    fi
    if (( new )) && cmp -s -- "${draft}" <(jobs_edit_template "${kind}" "${name}"); then
      rm -f -- "${before}" "${draft}"
      print -r -- "jobs: no change; nothing created | ${kind}=${name}"
      return 0
    fi
    if (( ! new )) && cmp -s -- "${draft}" "${file}"; then
      rm -f -- "${before}" "${draft}"
      print -r -- "jobs: no change | ${kind}=${name} file=$(ui::paths "${file}")"
      return 0
    fi
    jobs_edit_check "${draft}" "${kind}" && break
    if (( tty )) && ui::confirm "Edit ${name} again?"; then continue; fi
    rm -f -- "${before}"
    log::err "${kind} not saved; draft kept | draft='${draft}' fix='${CLI_NAME} jobs edit ${name}${${kind:#plugin}:+ --dep}'"
    return 1
  done
  rm -f -- "${before}"

  # In place: written beside the live file and renamed over it, so the agent never reads half a
  # file. Executable, unless it was a plugin turned off with chmod -x: an edit does not turn it on.
  local mode=755
  [[ -f "${file}" && ! -x "${file}" ]] && mode=644
  mkdir -p -- "${file:h}" || return 1
  cp -- "${draft}" "${file}.edit.$$" && chmod "${mode}" "${file}.edit.$$" && mv -f -- "${file}.edit.$$" "${file}" || {
    rm -f -- "${file}.edit.$$"
    log::err "could not put the ${kind} in place; draft kept | file='${file}' draft='${draft}'"
    return 1
  }
  rm -f -- "${draft}"
  verb=edit; (( new )) && verb=add
  print -r -- "${kind} ${name}: saved | tier=${tier} file=$(ui::paths "${file}")"
  if (( commit )); then
    local t=shared; [[ "${tier}" == ldf ]] && t=local
    local what="job ${name}"; [[ "${kind}" == dep ]] && what="job dep ${name}"
    tier::commit "${t}" "${CLI_NAME}: ${verb} ${what} (${t})" "${file}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${file}")"
  fi
  if [[ "${kind}" == plugin ]]; then
    print -r -- "next: ${CLI_NAME} jobs run ${name}"
  else
    print -r -- "next: ${CLI_NAME} jobs list"
  fi
}
