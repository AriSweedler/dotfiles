# cmd/status/edit.zsh — `dotfiles status --edit`: a commit plan for every uncommitted tracked
# path in the two tiers, written to a file, opened in $EDITOR, checked line by line, then run:
# one tier::commit per tier and message, one git restore per tier. Loaded by cmd/status.zsh;
# defines functions only.
#
# Entry point: status::edit [FILE]
# Reads: EDITOR, ARI_DOTFILES_DRY_RUN. Exports ARI_DOTFILES_NO_PUSH=1: this never pushes.
#
# A plan line: `<commit|restore|skip>  <shared|local>:<path>  [# message]`, the path relative to
# the tier's work tree (~ for shared, ~/.local for local). Submodule changes are comments only:
# they are committed in their own repos, and `dotfiles push` bumps their pointers.

# status::edit_dirty <tier>: one `XY\tpath` line per uncommitted tracked path (staged or not,
# submodules left out), in git's order. Nothing for a tier that is not here.
status::edit_dirty() {
  local tier="${1}" entry
  local -a entries
  is_repo_present "${tier}" || return 0
  entries=("${(@0)$(repo_git "${tier}" status --porcelain=v1 -z --untracked-files=no --ignore-submodules=all 2>/dev/null)}")
  local -i i
  for (( i = 1; i <= ${#entries}; i++ )); do
    entry="${entries[i]}"
    [[ -n "${entry}" ]] || continue
    print -r -- "${entry[1,2]}"$'\t'"${entry[4,-1]}"
    # A rename or copy is followed by its source path, which is not a line of its own.
    [[ "${entry[1]}" != [RC] ]] || i=$(( i + 1 ))
  done
}

# status::edit_scan: STATUS_DIRTY[<tier>:<path>]=XY for both tiers, and STATUS_DIRTY_ORDER the
# keys in git's order. Two git calls.
status::edit_scan() {
  typeset -gA STATUS_DIRTY=()
  typeset -ga STATUS_DIRTY_ORDER=()
  local tier xy rel
  for tier in shared local; do
    while IFS=$'\t' read -r xy rel; do
      [[ -n "${rel}" ]] || continue
      STATUS_DIRTY[${tier}:${rel}]="${xy}"
      STATUS_DIRTY_ORDER+=("${tier}:${rel}")
    done < <(status::edit_dirty "${tier}")
  done
}

# status::edit_git_text <tier>: the git command line a `would run:` names for a tier.
status::edit_git_text() {
  print -r -- "git --git-dir=${TIER_GIT_DIR[${1}]} --work-tree=${TIER_WORK_TREE[${1}]}"
}

# status::edit_file: the plan for STATUS_DIRTY: a header naming the actions, then per tier a
# heading, its `git diff --stat` as comments and one `skip  <tier>:<path>` line per path; then
# each submodule with uncommitted changes or a moved pointer, as comments.
status::edit_file() {
  local tier key line rec
  local -a stat f subdirty
  cat <<EOF
# ${CLI_NAME} status --edit: one line per uncommitted tracked path, <action>  <tier>:<path>  [# message]
# Change each 'skip' to one of:
#   commit    commit it in its tier; needs a '# message'. The lines of one tier with the
#             same message become one commit.
#   restore   discard the change (git restore --source=HEAD --staged --worktree): the path
#             goes back to its committed content. Confirmed by name on a terminal; a plan
#             with a restore is refused without one.
#   skip      leave it uncommitted
# Save and quit to see the plan. Nothing is pushed: run '${CLI_NAME} push' after.
# Lines starting with # are comments. Leaving every line 'skip' does nothing.
EOF
  for tier in shared local; do
    (( ${STATUS_DIRTY_ORDER[(I)${tier}:*]} )) || continue
    print -r -- ""
    print -r -- "# ── ${tier} (git ${TIER_ALIAS[${tier}]}, work tree $(ui::paths "${TIER_WORK_TREE[${tier}]}")) ──"
    if repo_git "${tier}" rev-parse -q --verify HEAD >/dev/null 2>&1; then
      stat=("${(@f)$(repo_git "${tier}" diff --stat HEAD --ignore-submodules=all 2>/dev/null)}")
    else
      stat=("${(@f)$(repo_git "${tier}" diff --cached --stat --ignore-submodules=all 2>/dev/null)}")
      print -r -- "# no commit yet: restore has nothing to restore from"
    fi
    for line in "${stat[@]}"; do [[ -z "${line}" ]] || print -r -- "#${line}"; done
    if ! repo_git "${tier}" diff --cached --quiet --ignore-submodules=all 2>/dev/null; then
      print -r -- "# staged changes: a commit here is refused until they are unstaged (git ${TIER_ALIAS[${tier}]} restore --staged …)"
    fi
    for key in "${STATUS_DIRTY_ORDER[@]}"; do
      [[ "${key}" == "${tier}:"* ]] && print -r -- "skip  ${key}"
    done
  done
  (( ${#SUBMODULES} )) || return 0
  status::_submodules
  local -a lines=()
  for rec in "${STATUS_SUBS[@]}"; do
    f=("${(@ps:\x1f:)rec}")
    [[ "${f[1]}" != - ]] || continue
    subdirty=("${(@f)$(git -C "${HOME}/${f[3]}" status --porcelain --untracked-files=no 2>/dev/null)}")
    subdirty=("${(@)subdirty:#}")
    if (( ${#subdirty} )); then
      lines+=("# ${f[3]}: ${#subdirty} uncommitted (git -C ~/${f[3]} commit …)")
      for line in "${subdirty[@]}"; do lines+=("#   ${line}"); done
    fi
    [[ "${f[1]}" != + ]] || lines+=("# ${f[3]}: ahead of its pointer; ${CLI_NAME} push bumps it")
  done
  (( ${#lines} )) || return 0
  print -r -- ""
  print -r -- "# ── submodules: not actionable here; each commits in its own repo ──"
  print -rl -- "${lines[@]}"
}

# status::edit_parse <plan file>: fills the caller's `choices`, one `N\taction\ttier\tpath\tmessage`
# per non-skip line, and prints `line N: problem | line='…'` on stderr for each bad line. Returns 1
# when any line is bad. A line names an action, then <tier>:<path> for a file that tier tracks
# (uncommitted or not: one that went clean since is dropped later, not refused), at most once per
# file, then '# message' (required for a commit, ignored otherwise).
status::edit_parse() {
  setopt localoptions extendedglob
  local file="${1}" line body item action message tier rel key
  local -a seen=() pending=()
  local -A tracked=()
  local -i n=0 bad=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$(( n + 1 ))
    body="${${line##[[:space:]]#}%%[[:space:]]#}"
    [[ -z "${body}" || "${body}" == '#'* ]] && continue
    action="${body%%[[:space:]]*}"
    if [[ "${action}" != (commit|restore|skip) ]]; then
      print -u2 -r -- "line ${n}: unknown action; use commit, restore or skip | line='${line}'"
      bad=1; continue
    fi
    item="${body#${action}}"; item="${item##[[:space:]]#}"
    message=""
    # The message starts at the first '#' after whitespace, so a path may hold a '#' of its own.
    if [[ "${item}" == '#'* ]]; then
      message="${item#\#}" item=""
    elif [[ "${item}" == *[[:space:]]'#'* ]]; then
      message="${item#*[[:space:]]\#}"
      item="${${item%%[[:space:]]\#*}%%[[:space:]]#}"
    fi
    message="${${message##[[:space:]]#}%%[[:space:]]#}"
    if [[ "${item}" != (shared|local):?* ]]; then
      print -u2 -r -- "line ${n}: expected <shared|local>:<path> after the action | line='${line}'"
      bad=1; continue
    fi
    tier="${item%%:*}" rel="${item#*:}"
    if [[ "${tier}" == local ]] && ! is_repo_present local; then
      print -u2 -r -- "line ${n}: the local tier is not here | line='${line}'"
      bad=1; continue
    fi
    if (( ${seen[(Ie)${item}]} )); then
      print -u2 -r -- "line ${n}: listed twice | item='${item}'"
      bad=1; continue
    fi
    seen+=("${item}")
    if [[ "${action}" == commit && -z "${message}" ]]; then
      print -u2 -r -- "line ${n}: a commit needs a message: end the line with '# message' | item='${item}'"
      bad=1; continue
    fi
    [[ "${action}" == commit ]] || message=""
    [[ "${action}" != skip ]] || continue
    pending+=("${n}"$'\t'"${action}"$'\t'"${tier}"$'\t'"${rel}"$'\t'"${message}")
  done < "${file}"
  # Tracked or not: one ls-files per tier for every path its lines name.
  local -a rels f
  local p
  for tier in shared local; do
    rels=()
    for p in "${pending[@]}"; do f=("${(@ps:\t:)p}"); [[ "${f[3]}" == "${tier}" ]] && rels+=(":(literal)${f[4]}"); done
    (( ${#rels} )) || continue
    for p in "${(@0)$(repo_git "${tier}" ls-files -z -- "${rels[@]}" 2>/dev/null)}"; do
      [[ -z "${p}" ]] || tracked[${tier}:${p}]=1
    done
  done
  for p in "${pending[@]}"; do
    f=("${(@ps:\t:)p}")
    key="${f[3]}:${f[4]}"
    if (( ! ${+tracked[${key}]} )); then
      print -u2 -r -- "line ${f[1]}: not a file the ${f[3]} tier tracks | item='${key}'"
      bad=1; continue
    fi
    choices+=("${p}")
  done
  return ${bad}
}

# status::edit_live: the caller's `choices` minus every path with no uncommitted change now (a
# note each on stderr), from a fresh scan. Run before the plan is shown and again before it runs.
status::edit_live() {
  local c
  local -a f kept=()
  status::edit_scan
  for c in "${choices[@]}"; do
    f=("${(@ps:\t:)c}")
    if (( ! ${+STATUS_DIRTY[${f[3]}:${f[4]}]} )); then
      log::warn "line ${f[1]}: no uncommitted change now; left alone | item='${f[3]}:${f[4]}' action='${f[2]}'"
      continue
    fi
    kept+=("${c}")
  done
  choices=("${kept[@]}")
}

# status::edit_groups: from the caller's `choices`, the caller's `groups` (one `tier\tmessage` per
# commit, in plan order), `members` (group → its paths, newline-ended) and `restores` (tier →
# its paths, newline-ended).
status::edit_groups() {
  local c key
  local -a f
  groups=() members=() restores=()
  for c in "${choices[@]}"; do
    f=("${(@ps:\t:)c}")
    if [[ "${f[2]}" == restore ]]; then
      restores[${f[3]}]+="${f[4]}"$'\n'
      continue
    fi
    key="${f[3]}"$'\t'"${f[5]}"
    (( ${+members[${key}]} )) || groups+=("${key}")
    members[${key}]+="${f[4]}"$'\n'
  done
}

# status::edit_refusals: what makes the plan unrunnable before anything changes, one log::err
# each: a commit in a tier with staged changes, a restore in a tier with no commit, a restore
# without a terminal. Returns 1 when any.
status::edit_refusals() {
  local tier g resume_file="${1}"
  local -i bad=0 tty="${2}"
  local -A committing=()
  for g in "${groups[@]}"; do committing[${g%%$'\t'*}]=1; done
  for tier in shared local; do
    if (( ${+committing[${tier}]} )) && ! repo_git "${tier}" diff --cached --quiet --ignore-submodules=all 2>/dev/null; then
      log::err "the ${tier} tier has staged changes; a commit would take them too | fix='git ${TIER_ALIAS[${tier}]} restore --staged <paths>, then ${CLI_NAME} status --edit ${resume_file}'"
      bad=1
    fi
    if [[ -n "${restores[${tier}]:-}" ]] && ! repo_git "${tier}" rev-parse -q --verify HEAD >/dev/null 2>&1; then
      log::err "the ${tier} tier has no commit to restore from | fix='skip those lines: ${CLI_NAME} status --edit ${resume_file}'"
      bad=1
    fi
  done
  # A dry run discards nothing, so it shows a restore without asking.
  if (( ! tty )) && ! is_dry_run && [[ -n "${restores[shared]:-}${restores[local]:-}" ]]; then
    log::err "a restore discards changes and needs a terminal to confirm it; nothing done | fix='${CLI_NAME} status --edit ${resume_file} (on a terminal), or skip the restore lines'"
    bad=1
  fi
  return ${bad}
}

# status::edit_show: the plan in a box: each commit (tier, message, paths), then the restores.
status::edit_show() {
  local g tier p
  local -a lines=() paths
  local -i width=$(( $(ui::cols) - 4 )) nrestore=0
  for g in "${groups[@]}"; do
    lines+=("$(ui::paint bold "$(ui::clip "${width}" "commit (${g%%$'\t'*}): ${g#*$'\t'}")")")
    for p in ${(f)members[${g}]}; do lines+=("$(ui::clip "${width}" "  ${p}")"); done
  done
  for tier in shared local; do
    [[ -n "${restores[${tier}]:-}" ]] || continue
    paths=(${(f)restores[${tier}]})
    nrestore+=${#paths}
    lines+=("$(ui::paint bold "restore (${tier}): discard the change")")
    for p in "${paths[@]}"; do lines+=("$(ui::clip "${width}" "  ${p}")"); done
  done
  local title="plan: ${#groups} commit(s), ${nrestore} restore(s), no push"
  is_dry_run && title+=" (dry run)"
  print -r -- ""
  ui::box --title "${title}" -- "${lines[@]}"
}

# status::edit_run: each commit (one tier::commit; tier::commit itself prints the would-run lines
# under --dry-run), then each tier's restore. Returns 1 when any failed; the rest still ran.
status::edit_run() {
  local g tier p
  local -a abs paths
  local -i i=0 failed=0
  for g in "${groups[@]}"; do
    i=$(( i + 1 ))
    tier="${g%%$'\t'*}"
    abs=()
    for p in ${(f)members[${g}]}; do abs+=("${TIER_WORK_TREE[${tier}]}/${p}"); done
    print -r -- ""
    print -r -- "$(ui::paint bold "[${i}/${#groups}] commit (${tier}): ${g#*$'\t'}")"
    tier::commit "${tier}" "${g#*$'\t'}" "${abs[@]}" || failed=$(( failed + 1 ))
  done
  for tier in shared local; do
    [[ -n "${restores[${tier}]:-}" ]] || continue
    paths=(${(f)restores[${tier}]})
    abs=()
    for p in "${paths[@]}"; do abs+=("${TIER_WORK_TREE[${tier}]}/${p}"); done
    print -r -- ""
    if is_dry_run; then
      print -r -- "would run: $(status::edit_git_text "${tier}") restore --source=HEAD --staged --worktree -- ${(j: :)abs}"
      continue
    fi
    print -r -- "$(ui::paint bold "restore (${tier}): ${(j:, :)paths}")"
    if ! repo_git "${tier}" restore --source=HEAD --staged --worktree -- "${abs[@]}"; then
      log::err "restore failed | tier='${tier}' paths='${(j: :)paths}'"
      failed=$(( failed + 1 ))
    fi
  done
  (( failed == 0 ))
}

# `status --edit [FILE]`: the plan file (STATE_DIR/status-plan.dfstatus, kept across runs, or FILE
# to resume one) opened in $EDITOR, then parsed. Bad lines: each reported with its number; on a
# terminal, offered for another edit, else exit 1 naming the --edit FILE that resumes. A good plan
# is shown, confirmed on a terminal (restores separately, by name), and run; then the tables.
status::edit() {
  local resume="${1:-}" file editor before
  local -a choices=() groups=()
  local -A members=() restores=()
  local -i tty=0 rc=0
  [[ -t 0 && -t 1 ]] && tty=1
  export ARI_DOTFILES_NO_PUSH=1
  if [[ -n "${resume}" ]]; then
    [[ -f "${resume}" ]] || usage_error "status --edit: no such plan file | file='${resume}'"
    file="${resume:a}"
  else
    status::edit_scan
    if (( ${#STATUS_DIRTY_ORDER} == 0 )); then
      print -r -- "status: nothing uncommitted in the tiers; no plan to write"
      return 0
    fi
    # The extension is the plan's filetype, for an editor to highlight. Not under RUN_DIR: a later
    # run may clear that, and the fix line names this file.
    file="${STATE_DIR}/status-plan.dfstatus"
    mkdir -p "${file:h}" || return 1
    status::edit_file > "${file}" || return 1
  fi
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  before="$(mktemp "${TMPDIR:-/tmp}/status-edit.XXXXXX")" || return 1
  while true; do
    cp -- "${file}" "${before}"
    if ! ${=editor} "${file}"; then
      rm -f -- "${before}"
      log::err "editor exited non-zero; nothing done | editor='${editor}' file='${file}'"
      return 1
    fi
    if [[ -z "${resume}" ]] && cmp -s -- "${before}" "${file}"; then
      rm -f -- "${before}"
      print -r -- "status: no change; nothing done | file=$(ui::paths "${file}")"
      return 0
    fi
    choices=()
    status::edit_parse "${file}" && break
    if (( tty )) && ui::confirm "Edit the plan again?"; then
      resume="${file}"   # an unchanged reopen is still a plan to read, not a "no change"
      continue
    fi
    rm -f -- "${before}"
    log::err "plan not run; fix the lines above, then | fix='${CLI_NAME} status --edit ${file}'"
    return 1
  done
  rm -f -- "${before}"
  status::edit_live
  if (( ${#choices} == 0 )); then
    print -r -- "status: nothing to do: every line is skip, or its path is clean now"
    return 0
  fi
  status::edit_groups
  status::edit_refusals "${file}" "${tty}" || return 1
  status::edit_show
  if (( tty )) && ! is_dry_run && (( ${#groups} )); then
    ui::confirm "Make ${#groups} commit(s)?" || rc=$?
    if (( rc != 0 )); then
      log::warn "declined; nothing done | file=$(ui::paths "${file}")"
      (( rc == 130 )) && return 130
      return 1
    fi
  fi
  if (( tty )) && ! is_dry_run && [[ -n "${restores[shared]:-}${restores[local]:-}" ]]; then
    local -a named=()
    local t p
    for t in shared local; do for p in ${(f)restores[${t}]:-}; do named+=("${t}:${p}"); done; done
    rc=0
    ui::confirm "Discard the changes to ${(j:, :)named}? This cannot be undone." || rc=$?
    if (( rc != 0 )); then
      (( rc == 130 )) && return 130
      log::warn "restores declined; those paths keep their changes"
      choices=(${(M)choices:#*$'\t'commit$'\t'*})
    fi
  fi
  # The scan again: a path committed or reverted elsewhere since the plan was shown is left alone.
  status::edit_live
  status::edit_groups
  rc=0
  status::edit_run || rc=1
  print -r -- ""
  status::print
  if is_dry_run; then
    print -r -- "next: ${CLI_NAME} status --edit $(ui::cmd_paths "${file}")   # without --dry-run, to run it"
  elif (( ${#groups} )); then
    print -r -- "next: ${CLI_NAME} push"
  else
    print -r -- "next: ${CLI_NAME} status"
  fi
  return ${rc}
}
