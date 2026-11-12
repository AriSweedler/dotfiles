# cmd/jobs/edit.zsh — `dotfiles jobs edit`: open a job plugin or dep in $EDITOR as a draft, check
# it, put it in place and commit it in its tier. Loaded by cmd/jobs.zsh; defines functions only.
#
# The live file is never edited: the resident agent rediscovers plugins and rereads their headers
# on every tick. The draft lives in JOBS_STATE_DIR/drafts until it passes, so a failed edit
# resumes where it left off. A plugin is found through the set (JOBS_ROOT) and edited at the tier
# file its link points to; a --new one is written in its tier and joins the set at the next
# dotfiles switch (nix/dotfiles-jobs.nix).

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
    for word in $(jobs_notifies "${file}"); do
      [[ "${word}" == (ok|fail) ]] || problems+=("'# notifies:' takes ok and fail, not '${word}'")
    done
  fi
  jobs_doc_problems "${file}" "${kind}"
  problems+=("${reply[@]/#/undocumented: }")
  (( ${#problems} == 0 )) && return 0
  print -u2 -rl -- "${problems[@]}"
  return 1
}

jobs_edit() {
  local -A opts; local -a args
  verb::parse jobs "$@"
  local name="${args[1]:-}" kind=plugin tier="" file="" root draft verb
  (( ${#args} <= 1 )) || usage_error "jobs edit takes one NAME | args='${args[*]}'"
  (( ${+opts[--dep]} )) && kind=dep
  (( ${+opts[--local]} )) && tier=ldf
  (( ${+opts[--global]} )) && tier=df
  (( ${+opts[--no-push]} )) && export ARI_DOTFILES_NO_PUSH=1
  local -i new=${+opts[--new]}
  [[ -n "${name}" ]] || usage_error "jobs edit needs a NAME | see='${CLI_NAME} jobs list'"
  [[ "${name}" != */* && "${name}" != .* && "${name}" != README.md ]] || usage_error "jobs edit: not a plugin name | name='${name}'"
  local set_root
  local -a roots
  if [[ "${kind}" == dep ]]; then
    set_root="${DEPS_ROOT}"; roots=("${DEPS_ROOT_DF}" "${DEPS_ROOT_LDF}")
  else
    set_root="${JOBS_ROOT}"; roots=("${JOBS_ROOT_DF}" "${JOBS_ROOT_LDF}")
  fi
  # The set's link, executable or not (a plugin turned off with chmod -x is still one to edit).
  local -a found=("${set_root}/${name}"(N-.))
  if (( new )); then
    (( ${#found} == 0 )) || { log::err "${kind} exists; edit it without --new | file='${found[1]:A}'"; return 1; }
    [[ -n "${tier}" ]] || tier=ldf
    if [[ "${tier}" == df ]]; then root="${roots[1]}"; else root="${roots[2]}"; fi
    file="${root}/${name}"
    [[ ! -e "${file}" ]] || { log::err "${kind} exists in its tier but not in the set yet; edit it there, then ${CLI_NAME} switch | file='${file}'"; return 1; }
  else
    [[ -z "${tier}" ]] || usage_error "jobs edit: --local and --global choose the tier of a --new ${kind} only"
    if (( ${#found} == 0 )); then
      log::err "no such ${kind}; --new creates one | name='${name}' fix='${CLI_NAME} jobs edit ${name}${${kind:#plugin}:+ --dep} --new'"
      return 1
    fi
    file="${found[1]:A}"
    jobs_tier_of "${found[1]}"; tier="${REPLY}"
  fi

  JOBS_EDIT_KIND="${kind}" JOBS_EDIT_NAME="${name}"
  edit::draft "${file}" "${JOBS_STATE_DIR}/drafts" jobs::_edit_template
  draft="${REPLY}"
  local -i rc=0
  edit::session "${draft}" --check jobs::_edit_check --what "${name}" ${${EDIT_RESUMED:#0}:+--changed} \
    --resume "${CLI_NAME} jobs edit ${name}${${kind:#plugin}:+ --dep}" || rc=$?
  if (( rc == 2 )); then
    rm -f -- "${draft}"
    if (( new )); then print -r -- "jobs: no change; nothing created | ${kind}=${name}"
    else print -r -- "jobs: no change | ${kind}=${name} file=$(ui::paths "${file}")"; fi
    return 0
  fi
  (( rc == 0 )) || return 1
  # A plugin turned off with chmod -x stays off; a new one is executable.
  local mode=""; (( new )) && mode=755
  edit::install "${draft}" "${file}" ${mode} || return 1
  verb=edit; (( new )) && verb=add
  print -r -- "${kind} ${name}: saved | tier=${tier} file=$(ui::paths "${file}")"
  if (( ${+opts[--no-commit]} )); then
    print -r -- "not committed | file=$(ui::paths "${file}")"
  else
    local t=shared; [[ "${tier}" == ldf ]] && t=local
    local what="job ${name}"; [[ "${kind}" == dep ]] && what="job dep ${name}"
    tier::commit "${t}" "${CLI_NAME}: ${verb} ${what} (${t})" "${file}" || return 1
  fi
  if (( new )); then print -r -- "next: ${CLI_NAME} switch puts ${name} in the set, then ${CLI_NAME} jobs list"
  elif [[ "${kind}" == plugin ]]; then print -r -- "next: ${CLI_NAME} jobs run ${name}"
  else print -r -- "next: ${CLI_NAME} jobs list"; fi
}

jobs::_edit_template() { jobs_edit_template "${JOBS_EDIT_KIND}" "${JOBS_EDIT_NAME}"; }
jobs::_edit_check() { jobs_edit_check "${1}" "${JOBS_EDIT_KIND}"; }
