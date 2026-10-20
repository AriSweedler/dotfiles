# dotfiles/cmd/logs.zsh — `dotfiles logs`: the push logs.

verb::define logs 'the push logs, per repo'
verb::usage logs 'logs [--repo NAME] [--previous]'
verb::about logs <<'EOF'
$(help::tilde "${LOG_DIR}")/<repo>.log holds the last push of each repo;
.log.bak.1 through .log.bak.${KEEP_BACKUPS} hold the runs before. NAME is 'shared',
'local' or a submodule path. --edit opens the same logs in \$EDITOR, all at
once, read-only for the vi family; it needs a terminal and writes nothing.
EOF
verb::flag logs '--repo NAME' "one repo's log instead of all of them"
verb::flag logs '--previous' 'the run before the last one (.log.bak.1)'
verb::edit logs logs::edit_cmd '[--repo NAME] [--previous]' 'open the logs in \$EDITOR to read, instead of printing them'
verb::env logs EDITOR 'the editor --edit opens' 'vi'
verb::env logs XDG_STATE_HOME 'the logs live under it, at dotfiles/push' '~/.local/state'

cmd_logs() {
  local -A opts; local -a args
  verb::parse logs "$@"
  (( ${#args} == 0 )) || usage_error "logs takes no positional arguments | args='${args[*]}'"
  (( ${+opts[--edit]} )) && { logs::edit_cmd "${@:#--edit}"; return; }
  local -a files
  local -i rc=0
  logs::files || rc=$?
  (( rc == 2 )) && return 0
  (( rc == 0 )) || return 1
  local file
  for file in "${files[@]}"; do
    print -r -- "${c_bold}=== ${file:t} ($(date -r "${file}" -u +%FT%TZ)) ===${c_rst}"
    cat "${file}"
  done
}

# logs::files: the caller's `files` from its `opts` (--repo, --previous); 1 for an unknown repo,
# 2 when there is no log yet (said once, here).
logs::files() {
  local suffix="" file
  (( ${+opts[--previous]} )) && suffix=".bak.1"
  if (( ${+opts[--repo]} )); then files=("$(log_file "${opts[--repo]}")${suffix}"); else files=("${LOG_DIR}"/*.log${suffix}(N)); fi
  if (( ${#files} == 0 )); then log::info "no push logs yet | dir='${LOG_DIR}'"; return 2; fi
  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || { log::err "no such log | file='${file}' valid_repos='shared, local, ${(j: :)SUBMODULES}'"; return 1; }
  done
}

# logs::edit_cmd [--repo NAME] [--previous]: the chosen logs open at once in $EDITOR, read-only.
logs::edit_cmd() {
  local -A opts; local -a args files
  verb::parse logs "$@"
  [[ -t 0 && -t 1 ]] || usage_error "logs --edit needs a terminal on stdin and stdout; 'dotfiles logs' prints them"
  local -i rc=0
  logs::files || rc=$?
  (( rc == 2 )) && return 0
  (( rc == 0 )) || return 1
  edit::open --readonly -- "${files[@]}" && return 0
  log::err "editor exited non-zero"
  return 1
}
