# dotfiles/cmd/status.zsh — `dotfiles status`: both tiers, the submodules, the last push of each repo.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_status() {
  cat <<EOF
dotfiles status   both tiers (branch, ahead/behind, uncommitted), the submodules, the last push per repo

  Submodule prefixes as 'git submodule status' prints them: space = at the committed pointer,
  + = elsewhere (a commit awaiting its bump), - = not initialized.
EOF
}

# One line for a tier from a single `git status`: the branch header (with ahead/behind once
# origin/main is known) and the count of uncommitted paths.
tier_line() {
  local repo="${1}"
  local -a lines
  lines=("${(@f)$(repo_git "${repo}" status --porcelain -b --untracked-files=no --ignore-submodules=dirty 2>/dev/null || true)}")
  lines=("${(@)lines:#}")
  if (( ${#lines} == 0 )); then print -r -- "${repo}: not cloned"; return 0; fi
  print -r -- "${repo}: ${lines[1]}  uncommitted=$(( ${#lines} - 1 ))"
}

# One line per declared submodule, in `git submodule status` shape without its cost:
# prefix (space = at the pointer, + = elsewhere, - = not initialized), sha, path, (heads/<branch>) or (detached).
submodule_lines() {
  if (( ${#SUBMODULES} == 0 )); then print -r -- "  none declared"; return 0; fi
  local meta repo pointer head branch prefix where
  local -A pointers
  # ls-tree: '160000 commit <sha>\t<path>' per submodule, one call for all.
  while IFS=$'\t' read -r meta repo; do pointers[${repo}]="${meta##* }"; done < <(repo_git shared ls-tree HEAD -- "${SUBMODULES[@]}" 2>/dev/null)
  for repo in "${SUBMODULES[@]}"; do
    pointer="${pointers[${repo}]:-}"
    if ! is_repo_present "${repo}"; then print -r -- "  -${pointer} ${repo}"; continue; fi
    head="$(repo_git "${repo}" rev-parse HEAD 2>/dev/null || true)"
    branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
    prefix=' '; [[ "${head}" == "${pointer}" ]] || prefix='+'
    where="heads/${branch}"; [[ -n "${branch}" ]] || where=detached
    print -r -- "  ${prefix}${head} ${repo} (${where})"
  done
}

cmd_status() {
  (( $# == 0 )) || usage_error "status takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}" logfile when verdict
  local -a logfiles=("${LOG_DIR}"/*.log(N))
  print -r -- "${c_bold}tiers${c_rst}"
  print -r -- "  $(tier_line shared)"
  if is_repo_present local; then print -r -- "  $(tier_line local)"; else print -r -- "  local: no repo (${CLI_NAME} setup)"; fi
  print -r -- "${c_bold}submodules${c_rst} (space = at the pointer, + = elsewhere, - = not initialized)"
  submodule_lines
  print -r -- "${c_bold}last push${c_rst} (${LOG_DIR}; 'dotfiles logs' for the whole run)"
  for logfile in "${logfiles[@]}"; do
    # The run's timestamp (its header) and verdict (its last line, minus the [LEVEL] tag).
    IFS=$'\t' read -r when verdict <<< "$(awk 'NR == 1 { when = $2 } { last = $0 }
      END { sub(/^\[[A-Z]+\] /, "", last); print when "\t" last }' "${logfile}")"
    printf '  %-26s %s  %s\n' "${logfile:t:r}" "${when}" "${verdict}"
  done
  (( ${#logfiles} > 0 )) || print -r -- "  none yet"
  if [[ "${TIMING}" == true ]]; then log::info "status | took='$(elapsed "${start}")s'"; fi
}
