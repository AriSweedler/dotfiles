# dotfiles/cmd/push.zsh — `dotfiles push`: token identity, per-repo pushes, pointer bumps.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_push() {
  cat <<EOF
dotfiles push [--submodules|--shared|--local|--no-submodules|--no-shared|--no-local] [--dry-run]   publish every tier (dfp)

  Pushes every submodule with something to push, in parallel (one log each), commits the shared
  tier's pointer bumps, then pushes the shared tier, all as ${DOTFILES_GITHUB_LOGIN} by its gh
  token; the local tier alongside, to its own remote with the ssh agent's key (its pre-push hook
  included). Repos already at origin are skipped silently; a submodule failure blocks the shared
  push. Human-only: Claude Code is denied 'dotfiles push'.

  --submodules | --shared | --local   only these parts (none = all three)
  --no-submodules | --no-shared | --no-local   leave a part out
  --dry-run                            the would-push lines, no network

  Logs: ${LOG_DIR}/<repo>.log ('dotfiles logs'). Once per machine: env -u GITHUB_TOKEN gh auth login
EOF
}

#######################################
# Get the login's token from gh and check whose it is. Sets TOKEN. The check is a network
# round trip, so the identity cache (same token fingerprint, same login, younger than
# IDENTITY_TTL_SECONDS) answers it for a known token. Runs before the first personal push only.
#######################################
load_token() {
  if ! TOKEN="$(env -u GITHUB_TOKEN gh auth token -u "${DOTFILES_GITHUB_LOGIN}" 2>/dev/null)" || [[ -z "${TOKEN}" ]]; then
    log::err "Personal account is not logged into gh | login='${DOTFILES_GITHUB_LOGIN}' fix='env -u GITHUB_TOKEN gh auth login   (HTTPS; pick ${DOTFILES_GITHUB_LOGIN})'"; return 1
  fi
  local fingerprint cached_fingerprint="" cached_login="" verified_at=0 who
  fingerprint="$(print -rn -- "${TOKEN}" | shasum -a 256 | awk '{print $1}')"
  if [[ -f "${IDENTITY_CACHE}" ]]; then read -r cached_fingerprint cached_login verified_at < "${IDENTITY_CACHE}" || true; fi
  if [[ "${cached_fingerprint}" == "${fingerprint}" && "${cached_login}" == "${DOTFILES_GITHUB_LOGIN}" && "${verified_at}" == <-> ]] &&
     (( EPOCHSECONDS - verified_at < IDENTITY_TTL_SECONDS )); then
    log::info "pushing as | login='${DOTFILES_GITHUB_LOGIN}' identity='cached'"; return 0
  fi
  who="$(GH_TOKEN="${TOKEN}" gh api user -q .login 2>/dev/null || true)"
  if [[ "${who}" != "${DOTFILES_GITHUB_LOGIN}" ]]; then log::err "Token identity mismatch | expected='${DOTFILES_GITHUB_LOGIN}' got='${who:-<none>}'"; return 1; fi
  mkdir -p "${STATE_DIR}"
  ( umask 077; print -r -- "${fingerprint} ${DOTFILES_GITHUB_LOGIN} ${EPOCHSECONDS}" > "${IDENTITY_CACHE}" )
  log::info "pushing as | login='${DOTFILES_GITHUB_LOGIN}' identity='verified'"
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
  local repo="${1}" branch sha url refspec out flag dest actor="${DOTFILES_GITHUB_LOGIN}"
  local -a auth=(-c credential.helper= -c 'credential.helper=!f() { echo "username=${DOTFILES_PUSH_LOGIN}"; echo "password=${DOTFILES_PUSH_TOKEN}"; }; f')
  print -r -- "# $(date -u +%FT%TZ) dotfiles push -> ${repo}"
  push_target "${repo}" || return 1
  refspec="refs/heads/${branch}:refs/heads/${branch}"; dest="${url}"
  if [[ "${repo}" == local ]]; then
    dest=origin; actor="the ssh agent's key"; auth=()
  else
    local -x DOTFILES_PUSH_LOGIN="${DOTFILES_GITHUB_LOGIN}" DOTFILES_PUSH_TOKEN="${TOKEN}"   # what the helper answers; git's environment, never argv
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
    push_target "${repo}" || return 1
    log::info "dry-run, would push | repo='${repo}' branch='${branch}' sha='${sha:0:7}' url='${url}' log='${logfile}'"; return 0
  fi
  if [[ "${repo}" != local && -z "${TOKEN}" ]]; then step token load_token || return 1; fi
  log_rotate "${logfile}" "${KEEP_BACKUPS}"
  STARTS[${repo}]="${EPOCHREALTIME}"
  { push_repo "${repo}" 2>&1 | strip_ansi > "${logfile}"; } &   # pipefail: the group exits with push_repo's rc
  PIDS[${repo}]=$!
}

# Wait for a repo's background push and report it in one line.
push_wait() {
  local repo="${1}" rc=0 took
  wait "${PIDS[${repo}]}" || rc=$?
  took="$(elapsed "${STARTS[${repo}]}")"
  if (( rc == 0 )); then log::info "pushed | repo='${repo}' took='${took}s' log='$(log_file "${repo}")'"; return 0; fi
  log::err "push failed | repo='${repo}' rc='${rc}' took='${took}s' see='dotfiles logs --repo ${repo}'"; return 1
}

#######################################
# Push a tier: absent or already at origin is one line and no push. The shared tier is
# awaited here; the local tier (its pre-push hook may run exo check --e2e, ~90 s) runs on
# while the rest pushes, and cmd_push awaits it last.
#######################################
push_tier() {
  local repo="${1}"
  if ! is_repo_present "${repo}"; then
    if [[ "${repo}" == shared ]]; then log::err "shared repo not cloned | git_dir='${TIER_GIT_DIR[shared]}' fix='dotfiles init'"; return 1; fi
    log::info "no local tier on this machine | hint='${CLI_NAME} apply local_dotfiles_repo'"; return 0
  fi
  if ! is_push_needed "${repo}"; then log::info "${repo} tier up to date | sha='$(repo_git "${repo}" rev-parse --short HEAD 2>/dev/null || true)'"; return 0; fi
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
    log::info "dry-run, would bump | repo='${repo}' from='${pointer:0:7}' to='${head:0:7}' message='${message}'"; return 0
  fi
  # `commit -- <path>` records this path alone; anything else staged in the shared tier stays staged.
  if ! out="$(repo_git shared commit -q -m "${message}" -- "${repo}" 2>&1)"; then
    print -r -- "${out}" >&2
    log::err "pointer bump refused | repo='${repo}' to='${head:0:7}' fix='see the hook output above'"; return 1
  fi
  log::info "bumped | repo='${repo}' to='${head:0:7}' commit='$(repo_git shared rev-parse --short HEAD)' message='${message}'"
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
    if ! is_repo_present "${repo}"; then log::warn "submodule not checked out; skipping | path='${repo}' fix='dotfiles init'"; continue; fi
    checked=$(( checked + 1 ))
    if ! is_push_needed "${repo}"; then published+=("${repo}"); continue; fi
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

# The local tier runs in the background while the submodules push (and their pointer
# bumps are committed), then the shared tier (only if every submodule made it), then
# the local result.
cmd_push() {
  # Selecting flags name the scope exactly (none = every part); excluding flags then remove from it.
  local -a only=() skip=()
  while (( $# > 0 )); do case "${1}" in
    --dry-run) export DOTFILES_DRY_RUN=1; shift ;;
    --submodules|--shared|--local)          only+=("${1#--}"); shift ;;
    --no-submodules|--no-shared|--no-local) skip+=("${1#--no-}"); shift ;;
    *) usage_error "push: unknown argument | argument='${1}'" ;;
  esac; done
  (( ${#only} == 0 )) || PUSH_SCOPE=("${(@)PUSH_PARTS:*only}")
  PUSH_SCOPE=("${(@)PUSH_SCOPE:|skip}")
  (( ${#PUSH_SCOPE} )) || usage_error "Empty push scope: every part excluded | parts='${(j:, :)PUSH_PARTS}'"
  local start="${EPOCHREALTIME}" failed=false scope="${(j:, :)PUSH_SCOPE}"
  check_prerequisites git gh || return 1
  if is_in_scope local; then push_tier local || failed=true; fi
  if is_in_scope submodules && ! push_submodules; then
    failed=true
    if is_in_scope shared; then log::err "shared tier not pushed: a submodule push failed | fix='dotfiles logs, fix, dotfiles push'"; fi
  elif is_in_scope shared; then
    push_tier shared || failed=true
  fi
  if [[ -n "${PIDS[local]:-}" ]]; then push_wait local || failed=true; fi
  if [[ "${failed}" == true ]]; then log::err "push failed | scope='${scope}' took='$(elapsed "${start}")s'"; return 1; fi
  log::info "push done | scope='${scope}' took='$(elapsed "${start}")s'"
}
