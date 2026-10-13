# dotfiles/cmd/status.zsh — `dotfiles status`: both tiers, the submodules, the last push of each repo.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_status() {
  cat <<EOF
both tiers, the submodules, the last push of each repo

${c_bold}Usage${c_rst}
  ${DF} status

  Each tier's branch, ahead/behind origin and uncommitted count; each
  submodule with the prefix 'git submodule status' prints (space = at the
  committed pointer, + = elsewhere, a commit awaiting its bump, - = not
  initialized); the timestamp and verdict of each repo's last push log.

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_DF_GIT_DIR)
      the shared tier's bare repo (default $(help::tilde "${ARI_DOTFILES_DF_GIT_DIR}"))
  $(ENV ARI_DOTFILES_LDF_GIT_DIR)
      the local tier's bare repo (default $(help::tilde "${ARI_DOTFILES_LDF_GIT_DIR}"))
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

# Every declared submodule as one record, fields split by \x1f (prefix, sha, path, where): prefix
# space = at the pointer, + = elsewhere, - = not initialized (sha is then the pointer, where empty);
# where is heads/<branch> or detached. Fills STATUS_SUBS; the plain lines and the card both read it.
status::_submodules() {
  typeset -ga STATUS_SUBS=()
  local meta repo pointer head branch prefix where
  local -A pointers
  # ls-tree: '160000 commit <sha>\t<path>' per submodule, one call for all.
  while IFS=$'\t' read -r meta repo; do pointers[${repo}]="${meta##* }"; done < <(repo_git shared ls-tree HEAD -- "${SUBMODULES[@]}" 2>/dev/null)
  for repo in "${SUBMODULES[@]}"; do
    pointer="${pointers[${repo}]:-}"
    if ! is_repo_present "${repo}"; then STATUS_SUBS+=("-"$'\x1f'"${pointer}"$'\x1f'"${repo}"$'\x1f'); continue; fi
    head="$(repo_git "${repo}" rev-parse HEAD 2>/dev/null || true)"
    branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
    prefix=' '; [[ "${head}" == "${pointer}" ]] || prefix='+'
    where="heads/${branch}"; [[ -n "${branch}" ]] || where=detached
    STATUS_SUBS+=("${prefix}"$'\x1f'"${head}"$'\x1f'"${repo}"$'\x1f'"${where}")
  done
}

# One line per declared submodule, in `git submodule status` shape without its cost:
# prefix (space = at the pointer, + = elsewhere, - = not initialized), sha, path, (heads/<branch>) or (detached).
submodule_lines() {
  if (( ${#SUBMODULES} == 0 )); then print -r -- "  none declared"; return 0; fi
  status::_submodules
  local rec
  local -a f
  for rec in "${STATUS_SUBS[@]}"; do
    f=("${(@ps:\x1f:)rec}")
    if [[ "${f[1]}" == - ]]; then print -r -- "  -${f[2]} ${f[3]}"
    else print -r -- "  ${f[1]}${f[2]} ${f[3]} (${f[4]})"
    fi
  done
}

# ── The cards (fancy only) and their pure helpers ────────────────────────────

# status::age <then-epoch> [now-epoch]: how long ago, coarsely: just now, 5m ago, 3h ago, 7d ago; ? when unknown.
status::age() {
  local then="${1:-}" now="${2:-${ARI_DOTFILES_NOW}}"
  [[ "${then}" == <-> && "${now}" == <-> ]] || { print -r -- "?"; return 0; }
  local -i d=$(( now - then ))
  if (( d < 60 )); then print -r -- "just now"
  elif (( d < 3600 )); then print -r -- "$(( d / 60 ))m ago"
  elif (( d < 86400 )); then print -r -- "$(( d / 3600 ))h ago"
  else print -r -- "$(( d / 86400 ))d ago"
  fi
}

# status::iso_epoch <YYYY-MM-DDTHH:MM:SSZ>: the epoch of a push log's UTC header stamp; nothing when unparseable.
status::iso_epoch() {
  local -x TZ=UTC
  local secs
  strftime -r -s secs '%Y-%m-%dT%H:%M:%SZ' "${1:-}" 2>/dev/null && print -r -- "${secs}"
  return 0
}

# status::drift <porcelain branch header>: '<status>\t<branch>\t<text>' for a tier, status ok or warn.
#   '## main...origin/main'              -> ok    main  ✓ in sync
#   '## main...origin/main [ahead 1]'    -> warn  main  ↑1 ahead · run dotfiles push
#   '## main...origin/main [behind 2]'   -> warn  main  ↓2 behind · run dotfiles pull
#   both                                 -> warn  main  ↑1 ↓2 diverged · run dotfiles pull
#   '## main' (no upstream), '[gone]'    -> warn  main  no upstream
status::drift() {
  setopt localoptions extendedglob
  local header="${1#\#\# }" branch track="" ahead="" behind=""
  branch="${header%%...*}"; branch="${branch%% \[*}"
  [[ "${branch}" != "No commits yet on "* ]] || branch="${branch#No commits yet on }"
  [[ "${header}" == *...* ]] && track="${header#*...}"
  [[ "${track}" == *(#b)ahead\ ([0-9]##)* ]] && ahead="${match[1]}"
  [[ "${track}" == *(#b)behind\ ([0-9]##)* ]] && behind="${match[1]}"
  local cli="${CLI_NAME:-dotfiles}"
  if [[ -z "${track}" || "${track}" == *\[gone\]* ]]; then print -r -- "warn"$'\t'"${branch}"$'\t'"no upstream"
  elif [[ -n "${ahead}" && -n "${behind}" ]]; then print -r -- "warn"$'\t'"${branch}"$'\t'"↑${ahead} ↓${behind} diverged · run ${cli} pull"
  elif [[ -n "${ahead}" ]]; then print -r -- "warn"$'\t'"${branch}"$'\t'"↑${ahead} ahead · run ${cli} push"
  elif [[ -n "${behind}" ]]; then print -r -- "warn"$'\t'"${branch}"$'\t'"↓${behind} behind · run ${cli} pull"
  else print -r -- "ok"$'\t'"${branch}"$'\t'"✓ in sync"
  fi
}

# status::push_verdict <last log line>: '<ok|fail>\t<branch@sha7 or empty>'; an [ERROR] line is a failure.
status::push_verdict() {
  setopt localoptions extendedglob
  local line="${1:-}" verdict=ok ref=""
  [[ "${line}" != "[ERROR]"* ]] || verdict=fail
  # The leading group stops the ref at a word boundary; a bare * would leave the shortest ref ('n@…').
  if [[ "${line}" == (#b)(|*[^[:alnum:]_./-])([[:alnum:]_./-]##)@([0-9a-f](#c7,40))([^0-9a-f]*|) ]]; then
    ref="${match[2]}@${match[3][1,7]}"
  fi
  print -r -- "${verdict}"$'\t'"${ref}"
}

# The tiers card's rows: name, branch, drift, and the uncommitted count when nonzero.
status::_tier_rows() {
  local repo header drift st branch text extra
  local -a lines parts
  for repo in shared local; do
    if ! is_repo_present "${repo}"; then
      STATUS_ROWS+=("${repo}"$'\t'"$(ui::paint grey -)"$'\t'"$(ui::paint fail "no repo · run ${CLI_NAME} init")"); continue
    fi
    lines=("${(@f)$(repo_git "${repo}" status --porcelain -b --untracked-files=no --ignore-submodules=dirty 2>/dev/null || true)}")
    lines=("${(@)lines:#}")
    if (( ${#lines} == 0 )); then STATUS_ROWS+=("${repo}"$'\t'"$(ui::paint grey -)"$'\t'"$(ui::paint fail "not cloned")"); continue; fi
    drift="$(status::drift "${lines[1]}")"
    parts=("${(@ps:\t:)drift}")
    st="${parts[1]}" branch="${parts[2]}" text="${parts[3]}"
    extra=""
    (( ${#lines} == 1 )) || extra="  $(ui::paint warn "$(( ${#lines} - 1 )) uncommitted")"
    STATUS_ROWS+=("${repo}"$'\t'"$(ui::paint cyan "${branch}")"$'\t'"$(ui::paint "${st}" "${text}")${extra}")
  done
}

# The submodules card's rows: short name, 7-char sha, branch or detached, where it stands against the pointer.
status::_submodule_rows() {
  if (( ${#SUBMODULES} == 0 )); then STATUS_ROWS+=("$(ui::paint grey "none declared")"); return 0; fi
  status::_submodules
  local rec where verdict
  local -a f
  for rec in "${STATUS_SUBS[@]}"; do
    f=("${(@ps:\x1f:)rec}")
    where="${f[4]#heads/}"
    case "${f[1]}" in
      -) verdict="$(ui::paint fail "- not initialized · run ${CLI_NAME} init")"; where="-" ;;
      +) verdict="$(ui::paint warn "+ ahead of pointer · bumped on push")" ;;
      *) verdict="$(ui::paint ok "✓ at pointer")" ;;
    esac
    STATUS_ROWS+=("${f[3]:t}"$'\t'"$(ui::paint grey "${f[2][1,7]:--}")"$'\t'"$(ui::paint cyan "${where}")"$'\t'"${verdict}")
  done
}

# The last-push card's rows: repo, ✓ or ✗, how long ago, branch@sha when the last line names one.
status::_push_rows() {
  local logfile when target last verdict epoch
  local -a parts
  for logfile in "${@}"; do
    IFS=$'\t' read -r when target last <<< "$(awk 'NR == 1 { when = $2; target = $NF } { last = $0 }
      END { print when "\t" target "\t" last }' "${logfile}")"
    [[ -n "${target}" && "${target}" != push ]] || target="${logfile:t:r}"
    verdict="$(status::push_verdict "${last}")"
    parts=("${(@ps:\t:)verdict}")
    epoch="$(status::iso_epoch "${when}")"
    STATUS_ROWS+=("${target:t}"$'\t'"$(ui::paint "${parts[1]}" "$(ui::glyph "${parts[1]}")")"$'\t'"$(ui::paint grey "$(status::age "${epoch}")")"$'\t'"$(ui::paint cyan "${parts[2]}")")
  done
  (( $# > 0 )) || STATUS_ROWS+=("$(ui::paint grey "none yet")")
}

# Three cards side by side when they fit the terminal, stacked otherwise. Four gum calls.
status::cards() {
  local -a boxes=() STATUS_ROWS
  local fn title box top
  local -i total=-1
  setopt localoptions extendedglob
  ui::_utf8 || local LC_ALL=en_US.UTF-8
  for fn title in _tier_rows tiers _submodule_rows submodules _push_rows "last push"; do
    STATUS_ROWS=()
    "status::${fn}" "${@}"
    box="$(ui::box --title "${title}" -- "${(@f)$(print -rl -- "${STATUS_ROWS[@]}" | ui::table --no-header --no-clip -)}")"
    boxes+=("${box}")
    top="${box%%$'\n'*}"; top="${top//${~UI_ANSI_PAT}/}"
    total=$(( total + ${(m)#top} + 1 ))  # not (( += )): a 0 result is status 1, and set -e ends status
  done
  if (( total <= $(ui::cols) )); then ui::join_h "${boxes[1]}" " " "${boxes[2]}" " " "${boxes[3]}"
  else print -r -- "${(F)boxes}"
  fi
}

cmd_status() {
  (( $# == 0 )) || usage_error "status takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}" logfile when verdict
  local -a logfiles=("${LOG_DIR}"/*.log(N))
  if ui::is_fancy; then
    status::cards "${logfiles[@]}"
    if [[ "${TIMING}" == true ]]; then log::info "status | took='$(elapsed "${start}")s'"; fi
    return 0
  fi
  print -r -- "${c_bold}tiers${c_rst}"
  print -r -- "  $(tier_line shared)"
  if is_repo_present local; then print -r -- "  $(tier_line local)"; else print -r -- "  local: no repo (${CLI_NAME} init)"; fi
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
