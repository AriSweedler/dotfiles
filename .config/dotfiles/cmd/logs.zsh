# dotfiles/cmd/logs.zsh — `dotfiles logs`: the push logs.

help_logs() {
  cat <<EOF
the push logs, per repo

${c_bold}Usage${c_rst}
  ${DF} logs [--repo NAME] [--previous]
  ${DF} logs --edit [--repo NAME] [--previous]

  $(help::tilde "${LOG_DIR}")/<repo>.log holds the last push of each repo;
  .log.bak.1 through .log.bak.${KEEP_BACKUPS} hold the runs before. NAME is 'shared',
  'local' or a submodule path.

  --edit opens the same logs in \$EDITOR (vi when unset), all at once, to
  read: read-only (-R) when the editor is vi, vim, nvim or view. It needs a
  terminal on stdin and stdout, and writes nothing.

${c_bold}Flags${c_rst}
  --repo NAME   one repo's log instead of all of them
  --previous    the run before the last one (.log.bak.1)
  --edit        open them in \$EDITOR instead of printing them

${c_bold}Env${c_rst}
  $(ENV EDITOR)
      the editor --edit opens (default vi)
  $(ENV XDG_STATE_HOME)
      the logs live under it, at dotfiles/push (default ~/.local/state)
EOF
}

cmd_logs() {
  local -a repo=() previous=() edit=()
  zparseopts -D -E -F -K -- -repo:=repo -previous=previous -edit=edit || usage_error "logs: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "logs takes no positional arguments | args='$*'"
  if (( ${#edit} )) && ! [[ -t 0 && -t 1 ]]; then
    usage_error "logs --edit needs a terminal on stdin and stdout; 'dotfiles logs' prints them"
  fi
  local suffix="" file
  local -a files
  (( ${#previous} )) && suffix=".bak.1"
  if (( ${#repo} )); then files=("$(log_file "${repo[2]}")${suffix}"); else files=("${LOG_DIR}"/*.log${suffix}(N)); fi
  if (( ${#files} == 0 )); then log::info "no push logs yet | dir='${LOG_DIR}'"; return 0; fi
  for file in "${files[@]}"; do
    if [[ ! -f "${file}" ]]; then log::err "no such log | file='${file}' valid_repos='shared, local, ${(j: :)SUBMODULES}'"; return 1; fi
    (( ${#edit} )) && continue
    print -r -- "${c_bold}=== ${file:t} ($(date -r "${file}" -u +%FT%TZ)) ===${c_rst}"
    cat "${file}"
  done
  (( ${#edit} )) || return 0
  logs::edit "${files[@]}"
}

# logs::edit <file>...: every file open at once in $EDITOR (its words split as the shell would),
# vi when unset or not found; -R for the editors that take it to mean read-only. Writes nothing.
logs::edit() {
  local -a editor=(${(z)${EDITOR:-vi}})
  editor=("${(@Q)editor}")
  command -v "${editor[1]}" >/dev/null 2>&1 || editor=(vi)
  [[ "${editor[1]:t}" != (vi|vim|nvim|view) ]] || editor+=(-R)
  "${editor[@]}" "$@" && return 0
  log::err "editor exited non-zero | editor='${editor[*]}'"
  return 1
}
