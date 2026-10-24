# dotfiles/cmd/push.zsh — `dotfiles push`: token identity, per-repo pushes, pointer bumps.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

verb::define push 'publish every tier: submodules, pointer bumps, shared, local'
verb::usage push 'push [--submodules] [--shared] [--local] [--dry-run]' \
  'push [--no-submodules] [--no-shared] [--no-local] [--dry-run]'
verb::about push <<'EOF'
Pushes every submodule with something to push, in parallel (one log each),
commits the shared tier's pointer bumps, then pushes the shared tier, all as
${ARI_DOTFILES_GITHUB_LOGIN} by its gh token; the local tier alongside, to its own remote
with the ssh agent's key (its pre-push hook included). Repos already at
origin are skipped silently; a submodule failure blocks the shared push.
Logs: $(help::tilde "${LOG_DIR}")/<repo>.log ('dotfiles logs'). Once per
machine: env -u GITHUB_TOKEN gh auth login. Human-only: Claude Code is denied
'dotfiles push'.

--edit writes one 'skip  <repo>  # <sha>' line per repo in scope with
something to push, under the commits it would push and the pointer bumps, to
$(help::tilde "${STATE_DIR}")/push-plan.dfpush and opens it in \$EDITOR. Change
'skip' to 'push' for each repo to publish. On save every line is checked
first: a repo whose HEAD moved since its sha was recorded is refused, and so
is 'push shared' while a submodule whose pointer it would bump is skipped.
Then one confirmation, and the push runs for exactly those repos.
EOF
verb::edit push push::edit_cmd '[FILE] [--<part>…] [--no-<part>…] [--dry-run]' \
  'choose the repos in a plan file (needs a terminal); FILE resumes a saved plan, and off a terminal runs it as saved'
verb::flag push '--submodules' 'only the submodules (a selecting flag names the scope exactly; none = all three parts)'
verb::flag push '--shared' 'only the shared tier'
verb::flag push '--local' 'only the local tier'
verb::flag push '--no-submodules' 'leave the submodules out'
verb::flag push '--no-shared' 'leave the shared tier out'
verb::flag push '--no-local' 'leave the local tier out'
verb::flag push '--dry-run' 'the would-push lines, no network (edit: for the repos the plan chose)'
verb::env push ARI_DOTFILES_GITHUB_LOGIN 'the GitHub account every personal push authenticates as, by its gh token' '${ARI_DOTFILES_GITHUB_LOGIN}'

plan::define push --actions 'push|skip' --item repo

#######################################
# Get the login's token from gh and check whose it is. Sets TOKEN. The check is a network
# round trip, so the identity cache (same token fingerprint, same login, younger than
# IDENTITY_TTL_SECONDS) answers it for a known token. Runs before the first personal push only.
#######################################
load_token() {
  if ! TOKEN="$(env -u GITHUB_TOKEN gh auth token -u "${ARI_DOTFILES_GITHUB_LOGIN}" 2>/dev/null)" || [[ -z "${TOKEN}" ]]; then
    log::err "Personal account is not logged into gh | login='${ARI_DOTFILES_GITHUB_LOGIN}' fix='env -u GITHUB_TOKEN gh auth login   (HTTPS; pick ${ARI_DOTFILES_GITHUB_LOGIN})'"; return 1
  fi
  local fingerprint cached_fingerprint="" cached_login="" verified_at=0 who
  fingerprint="$(print -rn -- "${TOKEN}" | shasum -a 256 | awk '{print $1}')"
  if [[ -f "${IDENTITY_CACHE}" ]]; then read -r cached_fingerprint cached_login verified_at < "${IDENTITY_CACHE}" || true; fi
  if [[ "${cached_fingerprint}" == "${fingerprint}" && "${cached_login}" == "${ARI_DOTFILES_GITHUB_LOGIN}" && "${verified_at}" == <-> ]] &&
     (( EPOCHSECONDS - verified_at < IDENTITY_TTL_SECONDS )); then
    log::info "pushing as | login='${ARI_DOTFILES_GITHUB_LOGIN}' identity='cached'"; return 0
  fi
  who="$(GH_TOKEN="${TOKEN}" gh api user -q .login 2>/dev/null || true)"
  if [[ "${who}" != "${ARI_DOTFILES_GITHUB_LOGIN}" ]]; then log::err "Token identity mismatch | expected='${ARI_DOTFILES_GITHUB_LOGIN}' got='${who:-<none>}'"; return 1; fi
  mkdir -p "${STATE_DIR}"
  ( umask 077; print -r -- "${fingerprint} ${ARI_DOTFILES_GITHUB_LOGIN} ${EPOCHSECONDS}" > "${IDENTITY_CACHE}" )
  log::info "pushing as | login='${ARI_DOTFILES_GITHUB_LOGIN}' identity='verified'"
}

#######################################
# Where a repo's push goes: sets branch, sha and url in the caller's scope (zsh dynamic
# scoping). Personal repos push by token, so their origin goes over https; the local tier
# keeps its origin as is. Returns 1 with the reason logged.
#######################################
push_target() {
  local repo="${1}" remote_url fix="git -C ~/${1} switch main   (/ari-dotfiles § Submodules step 1)"
  [[ -z "${TIER_ALIAS[${repo}]:-}" ]] || fix="git ${TIER_ALIAS[${repo}]} switch main"
  branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
  if [[ -z "${branch}" ]]; then log::err "Detached HEAD: nothing to push | repo='${repo}' fix='${fix}'"; return 1; fi
  if ! remote_url="$(repo_git "${repo}" remote get-url origin 2>/dev/null)"; then
    log::err "No such remote | repo='${repo}' remote='origin' remotes='$(repo_git "${repo}" remote | tr '\n' ' ')'"; return 1
  fi
  sha="$(repo_git "${repo}" rev-parse "refs/heads/${branch}")"
  url="${remote_url}"
  [[ "${repo}" != local ]] || return 0
  case "${remote_url}" in
    https://github.com/*)   ;;
    git@github.com:*)       url="https://github.com/${remote_url#git@github.com:}" ;;
    ssh://git@github.com/*) url="https://github.com/${remote_url#ssh://git@github.com/}" ;;
    *) log::err "Remote is not on github.com | repo='${repo}' url='${remote_url}'"; return 1 ;;
  esac
}

#######################################
# Push one repo's current branch; everything on stdout, which push_begin sends to the
# repo's log. One round trip: git's --porcelain verdict for the ref confirms the push (no
# ls-remote). Personal repos go to their https URL with a one-shot credential helper
# answering with the login's token (in the environment, never argv), and origin/<branch>
# is set to the pushed sha (no fetch) so hooks and is_push_needed see it; the local tier goes
# to origin as configured and git refreshes its tracking ref itself.
#######################################
push_repo() {
  local repo="${1}" branch sha url refspec out flag dest actor="${ARI_DOTFILES_GITHUB_LOGIN}"
  local -a auth=(-c credential.helper= -c 'credential.helper=!f() { echo "username=${ARI_DOTFILES_PUSH_LOGIN}"; echo "password=${ARI_DOTFILES_PUSH_TOKEN}"; }; f')
  print -r -- "# $(date -u +%FT%TZ) dotfiles push -> ${repo}"
  push_target "${repo}" || return 1
  refspec="refs/heads/${branch}:refs/heads/${branch}"; dest="${url}"
  if [[ "${repo}" == local ]]; then
    dest=origin; actor="the ssh agent's key"; auth=()
  else
    local -x ARI_DOTFILES_PUSH_LOGIN="${ARI_DOTFILES_GITHUB_LOGIN}" ARI_DOTFILES_PUSH_TOKEN="${TOKEN}"   # what the helper answers; git's environment, never argv
  fi
  log::info "Pushing | repo='${repo}' branch='${branch}' sha='${sha:0:7}' url='${url}' as='${actor}' head_author='$(repo_git "${repo}" log -1 --format='%an <%ae>' "${sha}")'"
  if ! out="$(repo_git "${repo}" "${auth[@]}" push --porcelain "${dest}" "${refspec}" 2>&1)"; then
    print -r -- "${out}"
    log::err "Push rejected | repo='${repo}' branch='${branch}' url='${url}'"; return 1
  fi
  print -r -- "${out}"
  # The ref's line: '<flag>\t<refspec>\t<summary>'; flag ' ' = fast-forward, '*' = new, '=' = up to date.
  flag="$(print -r -- "${out}" | awk -F'\t' -v ref="${refspec}" '$2 == ref { print substr($1, 1, 1) }')"
  case "${flag}" in
    ' '|'*') ;;
    '=')     log::info "Already there | repo='${repo}' branch='${branch}' sha='${sha:0:7}'" ;;
    *)       log::err "Remote ref does not match after push | repo='${repo}' branch='${branch}' flag='${flag:-none}'"; return 1 ;;
  esac
  [[ "${repo}" == local ]] || repo_git "${repo}" update-ref "refs/remotes/origin/${branch}" "${sha}"
  log::info "Pushed | ${branch}@${sha:0:7} -> ${url}"
}

#######################################
# True (0) when a repo has commits origin lacks, judged locally against the remote-tracking
# ref (refreshed by every push here and by pull): no network. Detached (after a pull)
# compares HEAD with origin/main. No tracking ref yet counts as needed; the push decides.
#######################################
is_push_needed() {
  local repo="${1}" branch local_ref=HEAD remote_ref=refs/remotes/origin/main
  branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
  if [[ -n "${branch}" ]]; then local_ref="refs/heads/${branch}"; remote_ref="refs/remotes/origin/${branch}"; fi
  repo_git "${repo}" rev-parse -q --verify "${remote_ref}" >/dev/null 2>&1 || return 0
  ! repo_git "${repo}" merge-base --is-ancestor "${local_ref}" "${remote_ref}" 2>/dev/null
}

#######################################
# Start a repo's push. Under --dry-run: the would-push line, no network. Else: the token
# (once; personal repos only), the rotated log, and push_repo in the background, recorded
# in PIDS/STARTS for push_wait. Returns 1 with the reason logged.
#######################################
push_begin() {
  local repo="${1}" branch sha url logfile
  logfile="$(log_file "${repo}")"
  if is_dry_run; then
    if ! push_target "${repo}"; then push::record "${repo}" failed; return 1; fi
    log::info "dry-run, would push | repo='${repo}' branch='${branch}' sha='${sha:0:7}' url='${url}' log='${logfile}'"
    push::record "${repo}" "would push" "${sha}"; return 0
  fi
  if [[ "${repo}" != local && -z "${TOKEN}" ]]; then
    step token load_token || { push::record "${repo}" "failed (token)"; return 1; }
  fi
  log_rotate "${logfile}" "${KEEP_BACKUPS}"
  STARTS[${repo}]="${EPOCHREALTIME}"
  { push_repo "${repo}" 2>&1 | strip_ansi > "${logfile}"; } &   # pipefail: the group exits with push_repo's rc
  PIDS[${repo}]=$!
}

# Wait for a repo's background push and report it in one line.
push_wait() {
  local repo="${1}" rc=0 took sha
  wait "${PIDS[${repo}]}" || rc=$?
  took="$(elapsed "${STARTS[${repo}]}")"
  sha="$(repo_git "${repo}" rev-parse -q --verify HEAD 2>/dev/null || true)"
  if (( rc == 0 )); then
    log::info "pushed | repo='${repo}' took='${took}s' log='$(log_file "${repo}")'"
    push::record "${repo}" pushed "${sha}" "${took}" "$(log_file "${repo}")"; return 0
  fi
  log::err "push failed | repo='${repo}' rc='${rc}' took='${took}s' see='dotfiles logs --repo ${repo}'"
  push::record "${repo}" failed "${sha}" "${took}" "$(log_file "${repo}")"; return 1
}

#######################################
# Push a tier: absent or already at origin is one line and no push. The shared tier is
# awaited here; the local tier (its pre-push hook may run exo check --e2e, ~90 s) runs on
# while the rest pushes, and push::main awaits it last.
#######################################
push_tier() {
  local repo="${1}"
  if ! is_repo_present "${repo}"; then
    if [[ "${repo}" == shared ]]; then
      log::err "shared repo not cloned | git_dir='${TIER_GIT_DIR[shared]}' fix='dotfiles init'"
      push::record shared "failed (not cloned)"; return 1
    fi
    log::info "no local tier on this machine | hint='${CLI_NAME} apply local_dotfiles_repo'"
    push::record local "skipped (no tier)"; return 0
  fi
  if [[ "${repo}" == local ]] && ! repo_git local remote get-url origin >/dev/null 2>&1; then
    log::info "local tier has no remote; nothing to push | hint='git ldf remote add origin <url>'"
    push::record local "skipped (no remote)"; return 0
  fi
  if ! is_push_needed "${repo}"; then
    log::info "${repo} tier up to date | sha='$(repo_git "${repo}" rev-parse --short HEAD 2>/dev/null || true)'"
    push::record "${repo}" "up to date" "$(repo_git "${repo}" rev-parse -q --verify HEAD 2>/dev/null || true)"; return 0
  fi
  push_begin "${repo}" || return 1
  [[ -n "${PIDS[${repo}]:-}" ]] || return 0   # dry-run: nothing running
  if [[ "${repo}" == local ]]; then log::info "local tier pushing in the background | log='$(log_file local)' note='its pre-push hook may run exo check --e2e'"; return 0; fi
  push_wait "${repo}"
}

#######################################
# The shared tier's pointer for a submodule follows its published HEAD: committed
# alone (that path only; message '<name>: bump to <sha> (<subject>)'), so the
# shared push after the submodules carries it. Returns 0 bumped, 2 nothing to do
# (pointer already there, checkout not ahead of it, no shared repo), 1 refused.
# Arguments:
#   $1 - submodule path
#######################################
bump_pointer() {
  local repo="${1}" pointer head count=1 subject message out
  is_repo_present shared || return 2
  pointer="$(repo_git shared ls-tree HEAD -- "${repo}" 2>/dev/null | awk '{print $3}')"
  head="$(repo_git "${repo}" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "${head}" && "${head}" != "${pointer}" ]] || return 2
  if [[ -n "${pointer}" ]] && ! repo_git "${repo}" merge-base --is-ancestor "${pointer}" "${head}" 2>/dev/null; then
    log::warn "pointer not bumped: checkout is not ahead of it | repo='${repo}' pointer='${pointer:0:7}' head='${head:0:7}' fix='dotfiles pull, or git -C ~/${repo} switch main'"
    return 2
  fi
  [[ -z "${pointer}" ]] || count="$(repo_git "${repo}" rev-list --count "${pointer}..${head}")"
  subject="$(repo_git "${repo}" log -1 --format=%s "${head}")"
  message="${repo:t}: bump to ${head:0:7} (${subject})"
  (( count <= 1 )) || message="${repo:t}: bump to ${head:0:7} (${count} commits, latest: ${subject})"
  if is_dry_run; then
    log::info "dry-run, would bump | repo='${repo}' from='${pointer:0:7}' to='${head:0:7}' message='${message}'"
    push::record "${repo:t} pointer" "would bump" "${head}"; return 0
  fi
  # `commit -- <path>` records this path alone; anything else staged in the shared tier stays staged.
  if ! out="$(repo_git shared commit -q -m "${message}" -- "${repo}" 2>&1)"; then
    print -r -- "${out}" >&2
    log::err "pointer bump refused | repo='${repo}' to='${head:0:7}' fix='see the hook output above'"
    push::record "${repo:t} pointer" failed "${head}"; return 1
  fi
  log::info "bumped | repo='${repo}' to='${head:0:7}' commit='$(repo_git shared rev-parse --short HEAD)' message='${message}'"
  push::record "${repo:t} pointer" bumped "${head}"
}

#######################################
# Push every checked-out submodule that needs it, in parallel; wait for all; bump the
# shared tier's pointer of every published one; report the counts; fail if any failed.
# Up-to-date submodules are silent.
#######################################
push_submodules() {
  if (( ${#SUBMODULES} == 0 )); then log::info "no submodules declared | file='${GITMODULES}'"; return 0; fi
  local repo rc checked=0 pushed=0 bumped=0 failed=0 verb=pushed start="${EPOCHREALTIME}"
  local -a running=() published=()
  is_dry_run && verb=would_push
  for repo in "${SUBMODULES[@]}"; do
    if ! is_repo_present "${repo}"; then
      log::warn "submodule not checked out; skipping | path='${repo}' fix='dotfiles init'"
      push::record "${repo}" "skipped (not checked out)"; continue
    fi
    checked=$(( checked + 1 ))
    if ! is_push_needed "${repo}"; then
      push::record "${repo}" "up to date" "$(repo_git "${repo}" rev-parse -q --verify HEAD 2>/dev/null || true)"
      # Its bump belongs to the shared push: a plan that skips shared commits none.
      is_allowed shared && published+=("${repo}")
      continue
    fi
    if ! is_allowed "${repo}"; then push::record "${repo}" "skipped (plan)"; continue; fi   # unpublished: no bump
    if ! push_begin "${repo}"; then failed=$(( failed + 1 )); continue; fi
    if is_dry_run; then pushed=$(( pushed + 1 )); published+=("${repo}"); continue; fi   # the plan printed counts as would_push
    running+=("${repo}")
  done
  if (( ${#running} > 0 )); then
    log::info "submodule pushes running | count='${#running}' logs='${LOG_DIR}'"
    for repo in "${running[@]}"; do
      if push_wait "${repo}"; then pushed=$(( pushed + 1 )); published+=("${repo}"); else failed=$(( failed + 1 )); fi
    done
  fi
  for repo in "${published[@]}"; do
    rc=0; bump_pointer "${repo}" || rc=$?
    case "${rc}" in 0) bumped=$(( bumped + 1 )) ;; 2) ;; *) failed=$(( failed + 1 )) ;; esac
  done
  log::info "submodules done | checked='${checked}' ${verb}='${pushed}' bumped='${bumped}' failed='${failed}' took='$(elapsed "${start}")s'"
  (( failed == 0 ))
}

# True (0) when a push part (local | submodules | shared) is in PUSH_SCOPE.
is_in_scope() { (( ${PUSH_SCOPE[(Ie)${1}]} )); }

# True (0) when a repo may push this run: always, unless push --edit's plan named the repos
# (PUSH_ALLOW, set in push::main's scope only under --edit).
is_allowed() { (( ! ${+PUSH_ALLOW} )) || (( ${PUSH_ALLOW[(Ie)${1}]} )); }

# The local tier runs in the background while the submodules push (and their pointer
# bumps are committed), then the shared tier (only if every submodule made it), then
# the local result. Under --edit the plan file chooses the repos first.
cmd_push() { push::main false "$@"; }
push::edit_cmd() { push::main true "$@"; }

# push::main EDIT ARGS..: EDIT true (or --edit anywhere in ARGS) chooses the repos in a plan first.
push::main() {
  local edit="${1}" part; shift
  local -A opts; local -a args
  verb::parse push "$@"
  (( ${+opts[--edit]} )) && edit=true
  (( ! ${+opts[--dry-run]} )) || export ARI_DOTFILES_DRY_RUN=1
  local edit_file="${args[1]:-}"
  [[ "${edit}" == true ]] || (( ${#args} == 0 )) || usage_error "push: unknown argument | argument='${args[1]}'"
  (( ${#args} <= 1 )) || usage_error "push --edit takes at most one FILE | args='${args[*]}'"
  # Selecting flags name the scope exactly (none = every part); excluding flags then remove from it.
  local -a only=() skip=()
  for part in "${PUSH_PARTS[@]}"; do
    (( ! ${+opts[--${part}]} )) || only+=("${part}")
    (( ! ${+opts[--no-${part}]} )) || skip+=("${part}")
  done
  (( ${#only} == 0 )) || PUSH_SCOPE=("${(@)PUSH_PARTS:*only}")
  PUSH_SCOPE=("${(@)PUSH_SCOPE:|skip}")
  (( ${#PUSH_SCOPE} )) || usage_error "Empty push scope: every part excluded | parts='${(j:, :)PUSH_PARTS}'"
  if [[ "${edit}" == true && -z "${edit_file}" ]] && ! [[ -t 0 && -t 1 ]]; then
    usage_error "push --edit opens \$EDITOR and needs a terminal; off one, pass a saved plan | fix='${CLI_NAME} push --edit FILE'"
  fi
  local start failed=false scope="${(j:, :)PUSH_SCOPE}"
  local -a PUSH_ROWS=()   # push::record's rows, for the closing table (dynamic scope: the push_* functions append)
  check_prerequisites git gh || return 1
  if [[ "${edit}" == true ]]; then
    local -a PUSH_ALLOW=()   # filled by push::edit; is_allowed reads it (dynamic scope)
    local PUSH_PLAN_PATH="${STATE_DIR}/push-plan.dfpush"   # push::edit points it at a resumed FILE
    push::edit "${edit_file}" || return
    (( ${#PUSH_ALLOW} )) || return 0
  fi
  start="${EPOCHREALTIME}"
  if is_in_scope local && is_allowed local; then push_tier local || failed=true; fi
  if is_in_scope submodules && ! push_submodules; then
    failed=true
    if is_in_scope shared && is_allowed shared; then
      log::err "shared tier not pushed: a submodule push failed | fix='dotfiles logs, fix, dotfiles push'"
      push::record shared "skipped (a submodule failed)"
    fi
  elif is_in_scope shared && is_allowed shared; then
    push_tier shared || failed=true
  fi
  if [[ -n "${PIDS[local]:-}" ]]; then push_wait local || failed=true; fi
  if [[ "${failed}" == true ]]; then
    log::err "push failed | scope='${scope}' took='$(elapsed "${start}")s'"
    push::show_summary
    [[ "${edit}" == false ]] || print -r -- "next: ${CLI_NAME} logs"
    return 1
  fi
  log::info "push done | scope='${scope}' took='$(elapsed "${start}")s'"
  push::show_summary
  if [[ "${edit}" == true ]]; then
    if is_dry_run; then print -r -- "next: ${CLI_NAME} push --edit ${PUSH_PLAN_PATH}"; else print -r -- "next: ${CLI_NAME} status"; fi
  fi
}

# --- push --edit: the plan file, one 'push|skip  <repo>  # <sha>' line per repo with something to push ---

# push::bump_pending <submodule>: 0 when bump_pointer would commit a new pointer for it now (its
# HEAD differs from the shared tier's pointer and is ahead of it), printing '<pointer|-> <head>'.
push::bump_pending() {
  local repo="${1}" pointer head
  is_repo_present shared && is_repo_present "${repo}" || return 1
  pointer="$(repo_git shared ls-tree HEAD -- "${repo}" 2>/dev/null | awk '{print $3}')"
  head="$(repo_git "${repo}" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "${head}" && "${head}" != "${pointer}" ]] || return 1
  [[ -z "${pointer}" ]] || repo_git "${repo}" merge-base --is-ancestor "${pointer}" "${head}" 2>/dev/null || return 1
  print -r -- "${pointer:--} ${head}"
}

# push::edit_candidates: the repos a plan lists, in run order, one per line: each in-scope repo
# that is_push_needed (the local tier only with a remote), and the shared tier also when an
# in-scope submodule's pointer bump would give it something to push.
push::edit_candidates() {
  local repo
  local -i bumps=0
  if is_in_scope local && is_repo_present local && repo_git local remote get-url origin >/dev/null 2>&1 && is_push_needed local; then
    print -r -- local
  fi
  if is_in_scope submodules; then
    for repo in "${SUBMODULES[@]}"; do
      is_repo_present "${repo}" || continue
      is_push_needed "${repo}" && print -r -- "${repo}"
      push::bump_pending "${repo}" >/dev/null && bumps+=1
    done
  fi
  if is_in_scope shared && is_repo_present shared && { (( bumps )) || is_push_needed shared; }; then
    print -r -- shared
  fi
  return 0
}

# push::unpushed <repo>: the commits a push would publish, as '#   <sha> <subject>' comment lines
# (twenty at most), after a '# <repo>  <branch>  <count>' line. The comparison is is_push_needed's.
push::unpushed() {
  local repo="${1}" branch local_ref=HEAD remote_ref=refs/remotes/origin/main count where
  local -i max=20
  branch="$(repo_git "${repo}" branch --show-current 2>/dev/null || true)"
  if [[ -n "${branch}" ]]; then local_ref="refs/heads/${branch}"; remote_ref="refs/remotes/origin/${branch}"; fi
  where="${branch:-detached}"
  if ! repo_git "${repo}" rev-parse -q --verify "${remote_ref}" >/dev/null 2>&1; then
    print -r -- "# ${repo}  ${where}  no ${remote_ref#refs/remotes/} yet: the push creates it"
    repo_git "${repo}" log --format='#   %h %s' -n "${max}" "${local_ref}" 2>/dev/null
    return 0
  fi
  count="$(repo_git "${repo}" rev-list --count "${remote_ref}..${local_ref}" 2>/dev/null || print 0)"
  print -r -- "# ${repo}  ${where}  $(plural "${count}" "commit ${remote_ref#refs/remotes/} lacks" "commits ${remote_ref#refs/remotes/} lacks")"
  repo_git "${repo}" log --format='#   %h %s' -n "${max}" "${remote_ref}..${local_ref}" 2>/dev/null
  (( count <= max )) || print -r -- "#   … $(( count - max )) more"
}

# push::edit_plan <candidate>…: the plan file's text. Every line starts as skip; its note is the
# repo's HEAD now, which the check holds a push line to.
push::edit_plan() {
  local repo sub pending
  plan::header push \
    "${CLI_NAME} push --edit: one line per repo with something to push; the note is its HEAD's sha." \
    "Change 'skip' to 'push' for each repo to publish:" \
    "  push   push it; a submodule's pointer bump is then committed in the shared tier" \
    "  skip   leave it unpushed (deleting the line is the same)" \
    "The sha is the repo's HEAD as this plan was written: a push line for a repo that has" \
    "moved since is refused. 'push shared' is refused while a submodule whose pointer it" \
    "would bump is skipped." \
    "Scope: ${(j:, :)PUSH_SCOPE}. Without --edit, '${CLI_NAME} push' pushes every repo listed."
  for repo in "$@"; do
    push::unpushed "${repo}"
    if [[ "${repo}" == shared ]] && is_in_scope submodules; then
      for sub in "${SUBMODULES[@]}"; do
        pending="$(push::bump_pending "${sub}")" || continue
        print -r -- "#   pointer bump: ${sub:t} ${${pending%% *}:0:7} -> ${${pending#* }:0:7}${${(M)@:#${sub}}:+ (once ${sub} is pushed)}"
      done
    fi
    plan::line skip "${repo}" "$(repo_git "${repo}" rev-parse --short=12 HEAD 2>/dev/null)"
    print -r -- ""
  done
}

# push::edit_repo <repo>: plan::parse's item check, a repo push::edit_candidates listed
# (PUSH_KNOWN, set by push::edit_check).
push::edit_repo() {
  (( ${PUSH_KNOWN[(Ie)${1}]} )) || { print -r -- "not a repo with something to push in this scope (repos: ${(j:, :)PUSH_KNOWN})"; return 1; }
}

# push::edit_check <plan file>: every line through plan::parse against the repos as they are now,
# then what only the whole plan shows: a push line's '# sha' must still start its repo's HEAD, and
# 'push shared' must not carry the pointer of a skipped submodule. Fills the caller's PUSH_ALLOW
# with the push lines' repos; prints one `line N: problem | …` per bad line on stderr; returns 1
# when any is bad.
push::edit_check() {
  setopt localoptions extendedglob
  local r repo sha head sub pending shared_line=""
  local -a reply f PUSH_KNOWN=("${(@f)$(push::edit_candidates)}")
  PUSH_KNOWN=("${(@)PUSH_KNOWN:#}")
  local -i bad=0
  PUSH_ALLOW=()
  plan::parse push "${1}" push::edit_repo || bad=1
  for r in "${reply[@]}"; do
    f=("${(@ps:\t:)r}")
    [[ "${f[1]}" == push ]] || continue
    repo="${f[2]}" sha="${f[3]%%[[:space:]]*}"
    if [[ "${sha}" != [0-9a-f](#c7,40) ]]; then
      print -u2 -r -- "line ${f[4]}: a push line needs the sha the plan recorded, as its '# note' | item='${repo}'"; bad=1; continue
    fi
    head="$(repo_git "${repo}" rev-parse HEAD 2>/dev/null || true)"
    if [[ "${head}" != "${sha}"* ]]; then
      print -u2 -r -- "line ${f[4]}: ${repo} moved since the plan was written | planned='${sha}' now='${head:0:12}' fix='${CLI_NAME} push --edit (a new plan)'"; bad=1; continue
    fi
    PUSH_ALLOW+=("${repo}")
    [[ "${repo}" != shared ]] || shared_line="${f[4]}"
  done
  # A skipped submodule publishes nothing, so its pointer must not ride the shared push.
  if [[ -n "${shared_line}" ]] && is_in_scope submodules; then
    for sub in "${SUBMODULES[@]}"; do
      (( ${PUSH_KNOWN[(Ie)${sub}]} && ! ${PUSH_ALLOW[(Ie)${sub}]} )) || continue
      pending="$(push::bump_pending "${sub}")" || continue
      print -u2 -r -- "line ${shared_line}: push shared while ${sub} is skipped; the shared tier would carry its unpublished pointer | pointer='${${pending%% *}:0:7}' head='${${pending#* }:0:7}' fix='push ${sub} too, or skip shared'"
      bad=1
    done
  fi
  return ${bad}
}

# push::edit [FILE]: the plan (written to push::main's PUSH_PLAN_PATH, or FILE to resume one) in
# one edit::session on a terminal, checked by push::edit_check; off a terminal FILE is checked as
# saved. A good plan is confirmed once on a terminal (not under --dry-run) and leaves the chosen
# repos in push::main's PUSH_ALLOW; 0 with it empty is nothing to push.
push::edit() {
  local resume="${1:-}" file
  local -i tty=0 rc=0
  [[ -t 0 && -t 1 ]] && tty=1
  if [[ -n "${resume}" ]]; then
    [[ -f "${resume}" ]] || usage_error "push --edit: no such plan file | file='${resume}'"
    file="${resume:a}"; PUSH_PLAN_PATH="${file}"
  else
    local -a candidates=("${(@f)$(push::edit_candidates)}")
    candidates=("${(@)candidates:#}")
    if (( ${#candidates} == 0 )); then
      print -r -- "nothing to push: every repo in scope is at origin | scope='${(j:, :)PUSH_SCOPE}'"
      return 0
    fi
    file="${PUSH_PLAN_PATH}"
    mkdir -p "${file:h}" || return 1
    push::edit_plan "${candidates[@]}" > "${file}" || return 1
  fi
  if (( tty )); then
    # A resumed FILE is read even when saved unchanged: the earlier edit is what is checked.
    edit::session "${file}" --check push::edit_check --what "the plan" \
      --resume "${CLI_NAME} push --edit ${file}" ${resume:+--changed} || rc=$?
    if (( rc == 2 )); then print -r -- "no change; nothing pushed"; return 0; fi
    (( rc == 0 )) || return 1
  elif ! push::edit_check "${file}"; then
    log::err "the plan not used; fix the problems above, then | file='${file}' fix='${CLI_NAME} push --edit ${file}'"
    return 1
  fi
  if (( ${#PUSH_ALLOW} == 0 )); then
    print -r -- "every line is skip; nothing pushed"
    return 0
  fi
  print -r -- "plan: push ${(j:, :)PUSH_ALLOW}"
  if (( tty )) && ! is_dry_run; then
    rc=0
    ui::confirm "Push $(plural "${#PUSH_ALLOW}" repo repos)?" || rc=$?
    if (( rc != 0 )); then
      log::warn "declined; nothing pushed | plan='${file}'"
      PUSH_ALLOW=()
      (( rc == 130 )) && return 130
      return 1
    fi
  fi
  return 0
}

# --- The closing table: one row per repo (and per pointer bump), terminal only ---

# push::record <repo> <result> [sha] [secs] [log] — one row of what happened, appended to
# push::main's PUSH_ROWS. result: pushed, up to date, would push, bumped, would bump, failed[ (why)],
# skipped (why). sha is any length; secs as elapsed prints them. A tab or newline in a field
# becomes a space, so a row is always one line of five fields.
push::record() {
  local -a f=("${1}" "${2}" "${3:-}" "${4:-}" "${5:-}")
  f=("${(@)f//[$'\t\n']/ }")
  PUSH_ROWS+=("${(pj:\t:)f}")
}

# push::summary_tsv <row>… — the rows push::record made, as TSV under a header: repo, result,
# the 7-character sha, took (<secs>s) and the log as ui::paths shows it. Pure.
push::summary_tsv() {
  local row REPLY
  local -a f
  print -r -- $'repo\tresult\tsha\ttook\tlog'
  for row in "${@}"; do
    f=("${(@ps:\t:)row}")
    ui::_paths "${f[5]:-}"
    print -r -- "${f[1]:-}"$'\t'"${f[2]:-}"$'\t'"${${f[3]:-}:0:7}"$'\t'"${f[4]:+${f[4]}s}"$'\t'"${REPLY}"
  done
}

# The ui status colour a result is painted in: done green, a plan yellow, failed red, no-op grey.
push::result_status() {
  case "${1}" in
    pushed|bumped)           print -r -- ok ;;
    would\ *)                print -r -- warn ;;
    failed*)                 print -r -- fail ;;
    *)                       print -r -- skip ;;
  esac
}

# The table of PUSH_ROWS on stderr, results painted, when fancy; nothing otherwise (plain output
# is the log lines alone).
push::show_summary() {
  ui::is_fancy || return 0
  (( ${#PUSH_ROWS} )) || return 0
  local line first=1
  local -a cells out=()
  for line in "${(@f)$(push::summary_tsv "${PUSH_ROWS[@]}")}"; do
    if (( first )); then out+=("${line}"); first=0; continue; fi
    cells=("${(@ps:\t:)line}")
    cells[2]="$(ui::paint "$(push::result_status "${cells[2]}")" "${cells[2]}")"
    out+=("${(pj:\t:)cells}")
  done
  print -rl -- "${out[@]}" | ui::table - >&2
}
