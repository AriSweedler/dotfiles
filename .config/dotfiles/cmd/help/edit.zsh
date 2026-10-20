# cmd/help/edit.zsh — `dotfiles help --edit [VERB]`: open a verb's file (or lib/dispatch.zsh) in
# $EDITOR at its help function, as a draft; check it, put it in place and commit it in the shared
# tier. Loaded by cmd/help.zsh; defines functions only.
#
# The live file is never edited: bin/dotfiles sources every cmd/*.zsh and lib/*.zsh, so one that
# does not parse stops every verb, this one included. The draft lives in
# <state>/drafts/help/NAME.zsh until it passes, so a failed edit resumes where it left off.

# help_edit_stub VERB: a help function in the house shape, for a verb without one. Its empty
# line 1 is no synopsis, so a stub saved as is does not pass; its Flags list what the verb parses.
help_edit_stub() {
  local verb="${1}" flag
  local -a reply
  help::verb_files "${verb}"
  help::parser_flags "${reply[@]}"
  print -r -- "help_${verb}() {"
  print -r -- "  cat <<EOF"
  print -r -- ""
  print -r -- ""
  print -r -- '${c_bold}Usage${c_rst}'
  print -r -- "  \${DF} ${verb}"
  print -r -- ""
  print -r -- "  What 'dotfiles ${verb}' does, in a paragraph."
  if (( ${#reply} )); then
    print -r -- ""
    print -r -- '${c_bold}Flags${c_rst}'
    for flag in "${reply[@]}"; do print -r -- "  ${flag}"; done
  fi
  print -r -- "EOF"
  print -r -- "}"
  print -r -- ""
}

# help_edit_with_stub FILE VERB: FILE's text with a stub help_VERB above cmd_VERB (else at the end).
help_edit_with_stub() {
  local file="${1}" verb="${2}" line stub
  local -i placed=0
  stub="$(help_edit_stub "${verb}")"$'\n\n'
  for line in "${(@f)mapfile[${file}]}"; do
    if (( ! placed )) && [[ "${line}" == "cmd_${verb}() "* ]]; then print -rn -- "${stub}"; placed=1; fi
    print -r -- "${line}"
  done
  (( placed )) || print -rn -- $'\n'"${stub}"
}

# help_edit_check DRAFT VERB: every problem with the draft on stderr, and 1 when there is any.
# VERB empty: the draft is lib/dispatch.zsh and its help() the top-level help.
help_edit_check() {
  local draft="${1}" verb="${2}" out err rc=0
  if ! out="$(zsh -n "${draft}" 2>&1)"; then
    print -u2 -r -- "syntax: ${${(f)out}[1]}"
    return 1
  fi
  err="$(mktemp "${TMPDIR:-/tmp}/help-edit.XXXXXX")" || return 1
  # The program as bin/dotfiles loads it, with the draft in place of its file; then the rule, then
  # the help rendered under the entrypoint's options.
  out="$(zsh -f -c '
    lib="$1" cmd="$2" draft="$3" verb="$4"
    for f in "${lib}"/*.zsh(N); do
      if [[ -z "${verb}" && "${f:t}" == dispatch.zsh ]]; then source "${draft}"; else source "${f}"; fi
    done
    for f in "${cmd}"/*.zsh(N); do
      if [[ -n "${verb}" && "${f:t}" == "${verb}.zsh" ]]; then source "${draft}"; else source "${f}"; fi
    done
    if [[ -n "${verb}" ]]; then
      (( ${+functions[cmd_${verb}]} )) || { print -u2 -r -- "defines no cmd_${verb}"; exit 1; }
      help::verb_gap "${verb}" "${draft}"
    else
      (( ${+functions[main]} && ${+functions[help]} )) || { print -u2 -r -- "defines no main or no help"; exit 1; }
      help::top_gap "${draft}"
    fi
    [[ -z "${REPLY}" ]] || { print -u2 -r -- "undocumented: ${REPLY}"; exit 1; }
    set -euo pipefail
    if [[ -n "${verb}" ]]; then help_verb "${verb}"; else help; fi' \
    help-edit "${ARI_DOTFILES_LIB}" "${ARI_DOTFILES_CMD}" "${draft}" "${verb}" 2> "${err}")" || rc=$?
  if (( rc != 0 )) || [[ -s "${err}" || -z "${out}" ]]; then
    if [[ -s "${err}" ]]; then cat -- "${err}" >&2
    elif (( rc != 0 )); then print -u2 -r -- "the help did not render (exit ${rc})"
    else print -u2 -r -- "the help renders nothing"
    fi
    rm -f -- "${err}"
    return 1
  fi
  rm -f -- "${err}"
}

help_edit() {
  setopt localoptions extendedglob
  zmodload zsh/mapfile
  local verb="${1}" commit="${2:-1}" file fn name base draft editor msg next line
  local -i stubbed=0 n tty=0
  if [[ -n "${verb}" ]]; then
    file="${ARI_DOTFILES_CMD}/${verb}.zsh"; fn="help_${verb}"; name="${verb}"
    msg="${CLI_NAME}: edit help for ${verb}"; next="${CLI_NAME} ${verb} --help"
    [[ -f "${file}" ]] || { log::err "no verb file | verb='${verb}' want='${file}'"; return 1; }
  else
    file="${ARI_DOTFILES_LIB}/dispatch.zsh"; fn=help; name=dotfiles
    msg="${CLI_NAME}: edit the top-level help"; next="${CLI_NAME} --help"
  fi
  base="${mapfile[${file}]}"
  if [[ -n "${verb}" && "${base}" != (|*$'\n')"${fn}() {"* ]]; then
    base="$(help_edit_with_stub "${file}" "${verb}")"$'\n'
    stubbed=1
  fi

  draft="${ARI_DOTFILES_STATE_DIR}/drafts/help/${name}.zsh"
  mkdir -p -- "${draft:h}" || return 1
  if [[ -f "${draft}" ]]; then
    log::info "resuming the draft a failed edit left | draft='${draft}'"
  else
    print -rn -- "${base}" > "${draft}" || return 1
  fi
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  [[ -t 0 && -t 1 ]] && tty=1
  while true; do
    # The editor opens at the help function: its line in the draft as it is now.
    n=1
    for line in "${(@f)mapfile[${draft}]}"; do
      [[ "${line}" == "${fn}() {"* ]] && break
      (( n++ ))
    done
    (( n <= ${#${(@f)mapfile[${draft}]}} )) || n=1
    if ! ${=editor} "+${n}" "${draft}"; then
      log::err "editor exited non-zero; draft kept, nothing changed | editor='${editor}' draft='${draft}'"
      return 1
    fi
    if [[ "${mapfile[${draft}]}" == "${base}" ]]; then
      rm -f -- "${draft}"
      if (( stubbed )); then print -r -- "help ${name}: no change; no help written | file=$(ui::paths "${file}")"
      else print -r -- "help ${name}: no change | file=$(ui::paths "${file}")"
      fi
      return 0
    fi
    help_edit_check "${draft}" "${verb}" && break
    if (( tty )) && ui::confirm "Edit the ${name} help again?"; then continue; fi
    log::err "help not saved; draft kept | draft='${draft}' fix='${CLI_NAME} help --edit${verb:+ ${verb}}'"
    return 1
  done

  # In place: written beside the live file and renamed over it, so no run sources half a file.
  cp -- "${draft}" "${file}.edit.$$" && chmod 644 "${file}.edit.$$" && mv -f -- "${file}.edit.$$" "${file}" || {
    rm -f -- "${file}.edit.$$"
    log::err "could not put the file in place; draft kept | file='${file}' draft='${draft}'"
    return 1
  }
  rm -f -- "${draft}"
  print -r -- "help ${name}: saved | file=$(ui::paths "${file}")"
  if (( commit )); then
    tier::commit shared "${msg}" "${file}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${file}")"
  fi
  print -r -- "next: ${next}"
}
