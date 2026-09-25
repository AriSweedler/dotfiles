# dotfiles/cmd/logs.zsh — `dotfiles logs`: the push logs.

help_logs() {
  cat <<EOF
the push logs, per repo

${c_bold}Usage${c_rst}
  ${DF} logs [--repo NAME] [--previous]

  $(help::tilde "${LOG_DIR}")/<repo>.log holds the last push of each repo;
  .log.bak.1 through .log.bak.${KEEP_BACKUPS} hold the runs before. NAME is 'shared',
  'local' or a submodule path.

${c_bold}Flags${c_rst}
  --repo NAME   one repo's log instead of all of them
  --previous    the run before the last one (.log.bak.1)

${c_bold}Env${c_rst}
  $(ENV XDG_STATE_HOME)
      the logs live under it, at dotfiles/push (default ~/.local/state)
EOF
}

cmd_logs() {
  local -a repo=() previous=()
  zparseopts -D -F -K -- -repo:=repo -previous=previous || usage_error "logs: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "logs takes no positional arguments | args='$*'"
  local suffix="" file
  local -a files
  (( ${#previous} )) && suffix=".bak.1"
  if (( ${#repo} )); then files=("$(log_file "${repo[2]}")${suffix}"); else files=("${LOG_DIR}"/*.log${suffix}(N)); fi
  if (( ${#files} == 0 )); then log::info "no push logs yet | dir='${LOG_DIR}'"; return 0; fi
  for file in "${files[@]}"; do
    if [[ ! -f "${file}" ]]; then log::err "no such log | file='${file}' valid_repos='shared, local, ${(j: :)SUBMODULES}'"; return 1; fi
    print -r -- "${c_bold}=== ${file:t} ($(date -r "${file}" -u +%FT%TZ)) ===${c_rst}"
    cat "${file}"
  done
}
