# cmd/help/edit.zsh — `dotfiles help --edit [VERB]`: open a verb's file (or lib/dispatch.zsh) in
# $EDITOR at its help function, as a draft; check it, put it in place and commit it in the shared
# tier. Loaded by cmd/help.zsh; defines functions only.
#
# The live file is never edited: bin/dotfiles sources every cmd/*.zsh and lib/*.zsh, so one that
# does not parse stops every verb, this one included. The draft lives in
# <state>/drafts/help/NAME.zsh until it passes, so a failed edit resumes where it left off.

# help_edit_stub VERB: a declaration in the house shape (lib/verb.zsh), for a verb without help.
# Its descriptions are empty, so a stub saved as is does not pass; a verb::flag per flag the verb
# parses by hand today, so moving it onto verb::parse is the next edit.
help_edit_stub() {
  local verb="${1}" flag
  local -a reply
  help::verb_files "${verb}"
  help::parser_flags "${reply[@]}"
  print -r -- "verb::define ${verb} ''"
  print -r -- "verb::usage ${verb} '${verb}'"
  print -r -- "verb::about ${verb} <<'EOF'"
  print -r -- "What 'dotfiles ${verb}' does, in a paragraph."
  print -r -- "EOF"
  for flag in "${reply[@]}"; do print -r -- "verb::flag ${verb} '${flag}' ''"; done
  print -r -- "verb::edit ${verb} --none ''"
  print -r -- ""
}

# help_edit_with_stub FILE VERB: FILE's text with the stub above cmd_VERB (else at the end).
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
  zmodload zsh/mapfile
  local verb="${1}" commit="${2:-1}" file name draft msg next at line
  local -i stubbed=0 n=0 rc=0
  if [[ -n "${verb}" ]]; then
    file="${ARI_DOTFILES_CMD}/${verb}.zsh" name="${verb}"
    msg="${CLI_NAME}: edit help for ${verb}" next="${CLI_NAME} ${verb} --help"
    [[ -f "${file}" ]] || { log::err "no verb file | verb='${verb}' want='${file}'"; return 1; }
    # A declared verb opens at its declaration; one not yet declared gets a declaration stub.
    if help::is_declared "${file}" "${verb}"; then at="verb::define ${verb} "
    elif [[ "${mapfile[${file}]}" == (|*$'\n')"help_${verb}() {"* ]]; then at="help_${verb}() {"
    else at="verb::define ${verb} "; stubbed=1; fi
  else
    file="${ARI_DOTFILES_LIB}/dispatch.zsh" name=dotfiles at="help() {"
    msg="${CLI_NAME}: edit the top-level help" next="${CLI_NAME} --help"
  fi
  edit::draft "${file}" "${ARI_DOTFILES_STATE_DIR}/drafts/help"
  draft="${REPLY}"
  (( stubbed && ! EDIT_RESUMED )) && help_edit_with_stub "${file}" "${verb}" > "${draft}"
  for line in "${(@f)mapfile[${draft}]}"; do (( ++n )); [[ "${line}" == "${at}"* ]] && break; done
  (( n <= ${#${(@f)mapfile[${draft}]}} )) || n=1
  HELP_EDIT_VERB="${verb}"
  edit::session "${draft}" --check help::_edit_check --line "${n}" --what "the ${name} help" \
    ${${EDIT_RESUMED:#0}:+--changed} --resume "${CLI_NAME} help --edit${verb:+ ${verb}}" || rc=$?
  if (( rc == 2 || ! stubbed && rc == 0 )) && edit::same "${draft}" "${file}"; then
    rm -f -- "${draft}"
    print -r -- "help ${name}: no change | file=$(ui::paths "${file}")"
    return 0
  fi
  if (( rc == 2 )); then
    rm -f -- "${draft}"
    print -r -- "help ${name}: no change; no help written | file=$(ui::paths "${file}")"
    return 0
  fi
  (( rc == 0 )) || return 1
  edit::install "${draft}" "${file}" 644 || return 1
  print -r -- "help ${name}: saved | file=$(ui::paths "${file}")"
  if (( commit )); then
    tier::commit shared "${msg}" "${file}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${file}")"
  fi
  print -r -- "next: ${next}"
}

help::_edit_check() { help_edit_check "${1}" "${HELP_EDIT_VERB}"; }
