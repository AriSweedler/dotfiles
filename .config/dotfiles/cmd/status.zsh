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

# ── The two tables (fancy only) and their pure helpers ───────────────────────

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

# status::sync <ahead|-> [behind]: '<ok|warn>\t<text>' from the counts against origin; '-' is no upstream.
status::sync() {
  local ahead="${1:-0}" behind="${2:-0}" cli="${CLI_NAME:-dotfiles}"
  if [[ "${ahead}" == - ]]; then print -r -- "warn"$'\t'"no upstream"
  elif (( ahead && behind )); then print -r -- "warn"$'\t'"↑${ahead} ↓${behind} diverged · run ${cli} pull"
  elif (( ahead )); then print -r -- "warn"$'\t'"↑${ahead} ahead · run ${cli} push"
  elif (( behind )); then print -r -- "warn"$'\t'"↓${behind} behind · run ${cli} pull"
  else print -r -- "ok"$'\t'"✓ in sync"
  fi
}

# status::drift <porcelain branch header>: '<status>\t<branch>\t<text>' for a tier, status ok or warn.
#   '## main...origin/main'              -> ok    main  ✓ in sync
#   '## main...origin/main [ahead 1]'    -> warn  main  ↑1 ahead · run dotfiles push
#   '## main...origin/main [behind 2]'   -> warn  main  ↓2 behind · run dotfiles pull
#   both                                 -> warn  main  ↑1 ↓2 diverged · run dotfiles pull
#   '## main' (no upstream), '[gone]'    -> warn  main  no upstream
status::drift() {
  setopt localoptions extendedglob
  local header="${1#\#\# }" branch track="" ahead=0 behind=0
  branch="${header%%...*}"; branch="${branch%% \[*}"
  [[ "${branch}" != "No commits yet on "* ]] || branch="${branch#No commits yet on }"
  [[ "${header}" == *...* ]] && track="${header#*...}"
  [[ "${track}" == *(#b)ahead\ ([0-9]##)* ]] && ahead="${match[1]}"
  [[ "${track}" == *(#b)behind\ ([0-9]##)* ]] && behind="${match[1]}"
  [[ -n "${track}" && "${track}" != *\[gone\]* ]] || ahead=-
  local sync; sync="$(status::sync "${ahead}" "${behind}")"
  print -r -- "${sync%%$'\t'*}"$'\t'"${branch}"$'\t'"${sync#*$'\t'}"
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

# status::last_push <logfile> [origin sha]: the 'last dotfiles push' cell, '✓ 4m ago' or '✗ 2d ago'
# from the log's header stamp and last line; '-' with no log. A push whose logged sha is not origin's
# (origin moved since, e.g. a push outside `dotfiles push`) is grey and names the sha it pushed (· was <sha>).
status::last_push() {
  local logfile="${1}" origin="${2:-}" when last verdict logged cell
  local -a parts
  [[ -f "${logfile}" ]] || { ui::paint grey -; return 0; }
  IFS=$'\t' read -r when last <<< "$(awk 'NR == 1 { when = $2 } { last = $0 } END { print when "\t" last }' "${logfile}")"
  verdict="$(status::push_verdict "${last}")"
  parts=("${(@ps:\t:)verdict}")
  logged="${parts[2]#*@}"
  cell="$(ui::glyph "${parts[1]}") $(status::age "$(status::iso_epoch "${when}")")"
  if [[ -n "${logged}" && -n "${origin}" && "${origin[1,7]}" != "${logged}" ]]; then
    ui::paint grey "${cell} · was ${logged}"
  else ui::paint "${parts[1]}" "${cell}"
  fi
}

# One tier's row in each table, from one `git status` and one `rev-parse HEAD @{u}`.
status::_tier_rows() {
  setopt localoptions extendedglob
  local repo="${1}" drift st branch text head="" up="" state
  local -a lines parts shas
  local dash="$(ui::paint grey -)"
  if ! is_repo_present "${repo}"; then
    STATUS_LOCAL+=("${repo}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(ui::paint fail "no repo · run ${CLI_NAME} init")")
    STATUS_REMOTE+=("${repo}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(status::last_push "$(log_file "${repo}")")")
    return 0
  fi
  lines=("${(@f)$(repo_git "${repo}" status --porcelain -b --untracked-files=no --ignore-submodules=dirty 2>/dev/null || true)}")
  lines=("${(@)lines:#}")
  if (( ${#lines} == 0 )); then
    STATUS_LOCAL+=("${repo}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(ui::paint fail "not cloned")")
    STATUS_REMOTE+=("${repo}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(status::last_push "$(log_file "${repo}")")")
    return 0
  fi
  drift="$(status::drift "${lines[1]}")"
  parts=("${(@ps:\t:)drift}")
  st="${parts[1]}" branch="${parts[2]}" text="${parts[3]}"
  [[ "${branch}" != "HEAD (no branch)" ]] || branch=detached
  # One line per rev that resolves: HEAD (none when unborn), then the upstream (none without one).
  shas=("${(@f)$(repo_git "${repo}" rev-parse HEAD '@{u}' 2>/dev/null || true)}")
  [[ "${shas[1]:-}" == [0-9a-f](#c40,64) ]] && head="${shas[1]}"
  [[ "${text}" != "no upstream" && "${shas[2]:-}" == [0-9a-f](#c40,64) ]] && up="${shas[2]}"
  state="$(ui::paint ok clean)"
  (( ${#lines} == 1 )) || state="$(ui::paint warn "$(( ${#lines} - 1 )) uncommitted")"
  STATUS_LOCAL+=("${repo}"$'\t'"$(ui::paint cyan "${branch}")"$'\t'"$(ui::paint grey "${head[1,7]:--}")"$'\t'"${state}")
  STATUS_REMOTE+=("${repo}"$'\t'"$(ui::paint grey "${up[1,7]:--}")"$'\t'"$(ui::paint "${st}" "${text}")"$'\t'"$(status::last_push "$(log_file "${repo}")" "${up}")")
}

# Each submodule's row in each table. One `rev-parse HEAD @{u} --symbolic-full-name HEAD`; then a
# `rev-list` for ahead/behind when it has an upstream, else `branch --show-current` for its branch.
status::_submodule_rows() {
  setopt localoptions extendedglob
  local meta repo pointer head up branch state sync counts
  local -A pointers
  local -a out parts
  local dash="$(ui::paint grey -)"
  (( ${#SUBMODULES} )) || return 0
  # ls-tree: '160000 commit <sha>\t<path>' per submodule, one call for all.
  while IFS=$'\t' read -r meta repo; do pointers[${repo}]="${meta##* }"; done < <(repo_git shared ls-tree HEAD -- "${SUBMODULES[@]}" 2>/dev/null)
  for repo in "${SUBMODULES[@]}"; do
    pointer="${pointers[${repo}]:-}"
    if ! is_repo_present "${repo}"; then
      STATUS_LOCAL+=("${repo:t}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(ui::paint fail "- not initialized · run ${CLI_NAME} init")")
      STATUS_REMOTE+=("${repo:t}"$'\t'"${dash}"$'\t'"${dash}"$'\t'"$(status::last_push "$(log_file "${repo}")")")
      continue
    fi
    out=("${(@f)$(repo_git "${repo}" rev-parse HEAD '@{u}' --symbolic-full-name HEAD 2>/dev/null || true)}")
    head="${out[1]:-}" up="" branch=""
    if (( ${#out} == 3 )); then
      up="${out[2]}" branch="${out[3]#refs/heads/}"
      counts="$(repo_git "${repo}" rev-list --left-right --count "HEAD...${up}" 2>/dev/null || true)"
      parts=(${=counts})
      sync="$(status::sync "${parts[1]:-0}" "${parts[2]:-0}")"
    else
      branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
      sync="$(status::sync -)"
    fi
    [[ -n "${branch}" ]] || branch=detached
    case "${head}" in
      "${pointer}") state="$(ui::paint ok "✓ at pointer")" ;;
      *) state="$(ui::paint warn "+ ahead of pointer · bumped on push")" ;;
    esac
    parts=("${(@ps:\t:)sync}")
    STATUS_LOCAL+=("${repo:t}"$'\t'"$(ui::paint cyan "${branch}")"$'\t'"$(ui::paint grey "${head[1,7]:--}")"$'\t'"${state}")
    STATUS_REMOTE+=("${repo:t}"$'\t'"$(ui::paint grey "${up[1,7]:--}")"$'\t'"$(ui::paint "${parts[1]}" "${parts[2]}")"$'\t'"$(status::last_push "$(log_file "${repo}")" "${up}")")
  done
}

# status::_width <text>: the widest line of <text> in display cells, colour escapes excluded.
status::_width() {
  setopt localoptions extendedglob
  local line bare
  local -i w=0
  for line in "${(@f)1}"; do bare="${line//${~UI_ANSI_PAT}/}"; (( ${(m)#bare} <= w )) || w=${(m)#bare}; done
  print -r -- "${w}"
}

# Two boxed tables, one row per repo (shared, local, each submodule): local (branch, HEAD, uncommitted
# or pointer state) and remote (origin's sha from the tracking ref, ahead/behind, the last
# `dotfiles push` from its log). Side by side when they fit the terminal; stacked otherwise, a table
# wider than the terminal clipped to it. Measured before gum draws: three gum calls, two when stacked.
status::cards() {
  local -a STATUS_LOCAL STATUS_REMOTE tables rows
  local repo
  local -i cols i
  setopt localoptions extendedglob
  ui::_utf8 || local LC_ALL=en_US.UTF-8
  STATUS_LOCAL=("repo"$'\t'"branch"$'\t'"HEAD"$'\t'"state")
  STATUS_REMOTE=("repo"$'\t'"origin"$'\t'"sync"$'\t'"last dotfiles push")
  for repo in shared local; do status::_tier_rows "${repo}"; done
  status::_submodule_rows
  tables=("$(print -rl -- "${STATUS_LOCAL[@]}" | ui::table --no-clip -)" "$(print -rl -- "${STATUS_REMOTE[@]}" | ui::table --no-clip -)")
  cols="$(ui::cols)"
  # A box is its widest line plus a border and a space of padding on each side.
  if (( $(status::_width "${tables[1]}") + $(status::_width "${tables[2]}") + 9 <= cols )); then
    ui::join_h "$(ui::box --title local -- "${(@f)tables[1]}")" " " "$(ui::box --title remote -- "${(@f)tables[2]}")"
    return
  fi
  for (( i = 1; i <= 2; i++ )); do
    if (( $(status::_width "${tables[i]}") + 4 > cols )); then
      if (( i == 1 )); then rows=("${STATUS_LOCAL[@]}"); else rows=("${STATUS_REMOTE[@]}"); fi
      tables[i]="$(print -rl -- "${rows[@]}" | COLUMNS=$(( cols - 4 )) ui::table -)"
    fi
  done
  ui::box --title local -- "${(@f)tables[1]}"
  ui::box --title remote -- "${(@f)tables[2]}"
}

cmd_status() {
  (( $# == 0 )) || usage_error "status takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}" logfile when verdict
  local -a logfiles=("${LOG_DIR}"/*.log(N))
  if ui::is_fancy; then
    status::cards
    if [[ "${TIMING}" == true ]]; then log::info "status | took='$(elapsed "${start}")s'"; fi
    return 0
  fi
  print -r -- "${c_bold}tiers${c_rst}"
  print -r -- "  $(tier_line shared)"
  if is_repo_present local; then print -r -- "  $(tier_line local)"; else print -r -- "  local: no repo (${CLI_NAME} init)"; fi
  print -r -- "${c_bold}submodules${c_rst} (space = at the pointer, + = elsewhere, - = not initialized)"
  submodule_lines
  print -r -- "${c_bold}last push${c_rst} ($(ui::paths "${LOG_DIR}"); 'dotfiles logs' for the whole run)"
  for logfile in "${logfiles[@]}"; do
    # The run's timestamp (its header) and verdict (its last line, minus the [LEVEL] tag).
    IFS=$'\t' read -r when verdict <<< "$(awk 'NR == 1 { when = $2 } { last = $0 }
      END { sub(/^\[[A-Z]+\] /, "", last); print when "\t" last }' "${logfile}")"
    printf '  %-26s %s  %s\n' "${logfile:t:r}" "${when}" "${verdict}"
  done
  (( ${#logfiles} > 0 )) || print -r -- "  none yet"
  if [[ "${TIMING}" == true ]]; then log::info "status | took='$(elapsed "${start}")s'"; fi
}
