# step dotfiles_repo — the shared tier: bare repo at ~/dotfiles.git (renamed from the pre-harness
# ~/dotfiles), tracking origin, HOME checked out, hooks wired, submodules initialized,
# origin/main known, nothing dirty. Every fix is idempotent: `dotfiles init` (setup's repo
# group) runs this after every pull.
step::declare dotfiles_repo --group repo \
  --desc "shared dotfiles bare repo cloned, tracking origin, checked out into HOME, hooks wired"

dotfiles_repo::origin_url() { git --git-dir="${1}" config remote.origin.url 2>/dev/null || true; }
dotfiles_repo::has_origin() { [[ -n "$(dotfiles_repo::origin_url "${1}")" ]]; }
# The config a bare clone lacks, key=value per line: the fetch refspec (remote-tracking refs, so
# status knows ahead/behind), main's upstream (so pull works) and, when the clone fetches over
# something else (https: a fresh machine has no key yet), the ssh push url, so `git df push` uses
# this machine's key. Empty ARI_DOTFILES_PUSH_URL = no push url.
dotfiles_repo::tracking() {
  local git_dir="${1}"
  print -r -- 'remote.origin.fetch=+refs/heads/*:refs/remotes/origin/*'
  print -r -- 'branch.main.remote=origin'
  print -r -- 'branch.main.merge=refs/heads/main'
  [[ -z "${ARI_DOTFILES_PUSH_URL}" || "$(dotfiles_repo::origin_url "${git_dir}")" == "${ARI_DOTFILES_PUSH_URL}" ]] \
    || print -r -- "remote.origin.pushurl=${ARI_DOTFILES_PUSH_URL}"
}
# The tracking keys whose value differs. Only a repo with an origin tracks.
dotfiles_repo::tracking_missing() {
  local git_dir="${1}" kv
  dotfiles_repo::has_origin "${git_dir}" || return 0
  for kv in "${(@f)$(dotfiles_repo::tracking "${git_dir}")}"; do
    [[ "$(git --git-dir="${git_dir}" config "${kv%%=*}" 2>/dev/null || true)" == "${kv#*=}" ]] || print -r -- "${kv}"
  done
}
dotfiles_repo::is_bare_repo() { [[ -f "${1}/HEAD" && ! -d "${1}/.git" ]]; }
dotfiles_repo::is_origin_main_known() { git --git-dir="${1}" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; }
# Submodule paths from ~/.gitmodules, read now: env.zsh's SUBMODULES predates a checkout this apply makes.
dotfiles_repo::submodules() {
  git config -f "${HOME}/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true
}

check::dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_DF_GIT_DIR}" legacy="${LEGACY_SHARED_GIT_DIR}"
  if [[ -d "${legacy}" ]] && dotfiles_repo::is_bare_repo "${legacy}"; then
    if [[ -e "${git_dir}" ]]; then
      verdict fail legacy_conflict -m -d "a bare repo at the pre-harness path and at the current one; keep one | legacy='${legacy}' current='${git_dir}'" -f "compare ${legacy} and ${git_dir}; remove one"
      return 0
    fi
    verdict fail legacy_path -d "shared bare repo still at the pre-harness path | legacy='${legacy}' current='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if [[ ! -d "${git_dir}" ]]; then
    verdict fail missing_bare_repo -d "no bare repo | git_dir='${git_dir}' remote='${ARI_DOTFILES_REMOTE}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if ! git --git-dir="${git_dir}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    verdict fail missing_bare_repo -d "repo has no HEAD | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  local -a missing=("${(@f)$(dotfiles_repo::tracking_missing "${git_dir}")}")
  missing=("${(@)missing:#}")
  if (( ${#missing} )); then
    verdict fail tracking -d "tracking config missing | keys='${(j:, :)${(@)missing%%=*}}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if tier::is_worktree_unpopulated "${git_dir}" "${HOME}" \
     && [[ -n "$(git --git-dir="${git_dir}" ls-tree -r --name-only HEAD 2>/dev/null | head -n 1)" ]]; then
    verdict fail not_checked_out -d "bare repo exists but HOME was never checked out | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  local hooks
  hooks="$(tier::hooks_path "${git_dir}")"
  if [[ "${hooks}" != "${ARI_DOTFILES_DF_HOOKS}" ]]; then
    verdict fail hooks_path -d "core.hooksPath='${hooks}' expected='${ARI_DOTFILES_DF_HOOKS}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if [[ -f "${HOME}/.gitmodules" ]]; then
    local sub_status uninit drifted
    sub_status="$(git -C "${HOME}" --git-dir="${git_dir}" --work-tree="${HOME}" submodule status 2>/dev/null || true)"
    uninit="$(print -r -- "${sub_status}" | awk '/^-/ {print $2}')"
    drifted="$(print -r -- "${sub_status}" | awk '/^\+/ {print $2}')"
    if [[ -n "${uninit}" ]]; then
      verdict fail submodule_uninitialized -d "submodule not checked out | paths='${uninit//$'\n'/, }'" -f "${CLI_NAME} apply dotfiles_repo"
      return 0
    fi
    if [[ -n "${drifted}" ]]; then
      verdict warn submodule_drift -d "checkout differs from the committed pointer | paths='${drifted//$'\n'/, }'" -f "cd ~ && git df submodule update   (or commit the new pointer)"
      return 0
    fi
  fi
  if dotfiles_repo::has_origin "${git_dir}" && ! dotfiles_repo::is_origin_main_known "${git_dir}"; then
    verdict fail no_origin_main -d "origin/main unknown: never fetched | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  local dirty
  dirty="$(git --git-dir="${git_dir}" --work-tree="${HOME}" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "${dirty}" ]]; then
    local -a lines=("${(f)dirty}")
    verdict warn uncommitted -d "$(plural "${#lines}" 'uncommitted file' 'uncommitted files')" -f "git df status"
    return 0
  fi
  verdict ok clean -d "git_dir='${git_dir}' hooks='${hooks}'"
}

# In order, each a no-op once done: rename the pre-harness repo, clone, tracking config, the
# checkout, hooks, submodules, the first fetch. The checkout fails, listing the conflicting files
# in the log, when HOME already holds files it would overwrite; nothing is moved on the user's behalf.
apply::dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_DF_GIT_DIR}" legacy="${LEGACY_SHARED_GIT_DIR}" kv
  if [[ -d "${legacy}" ]] && dotfiles_repo::is_bare_repo "${legacy}"; then
    if [[ -e "${git_dir}" ]]; then
      log::err "legacy and current bare repo both exist; keep one | legacy='${legacy}' current='${git_dir}'"
      return 1
    fi
    run_mut mv "${legacy}" "${git_dir}" || return 1
  fi
  if [[ ! -d "${git_dir}" ]]; then
    run_mut git clone --bare "${ARI_DOTFILES_REMOTE}" "${git_dir}" || return 1
  fi
  if dotfiles_repo::has_origin "${git_dir}"; then
    for kv in "${(@f)$(dotfiles_repo::tracking_missing "${git_dir}")}"; do
      [[ -n "${kv}" ]] || continue
      run_mut git --git-dir="${git_dir}" config "${kv%%=*}" "${kv#*=}" || return 1
    done
  elif [[ ! -d "${git_dir}" ]]; then
    # A dry run: the clone above was only logged, so its tracking can only be named.
    local -a keys=("${(@f)$(dotfiles_repo::tracking "${git_dir}")}")
    log::info "dry-run, would set tracking config | keys='${(j:, :)${(@)keys%%=*}}'"
  fi
  if tier::is_worktree_unpopulated "${git_dir}" "${HOME}"; then
    if ! run_mut git --git-dir="${git_dir}" --work-tree="${HOME}" checkout; then
      log::err "checkout failed; move the listed files aside and re-run | work_tree='${HOME}'"
      return 1
    fi
  fi
  tier::ensure_hooks_path "${git_dir}" "${ARI_DOTFILES_DF_HOOKS}" || return 1
  # Only the never-initialized submodules: `update` would detach an initialized one onto the
  # pointer, and a checkout ahead of the pointer is a commit awaiting its bump, not drift.
  local -a submodules=("${(@f)$(dotfiles_repo::submodules)}") uninit=()
  local sub
  for sub in "${(@)submodules:#}"; do
    [[ -e "${HOME}/${sub}/.git" ]] || uninit+=("${sub}")
  done
  if (( ${#uninit} )); then
    run_mut git -C "${HOME}" --git-dir="${git_dir}" --work-tree="${HOME}" submodule update --init -- "${uninit[@]}" || return 1
  fi
  if dotfiles_repo::has_origin "${git_dir}" && ! dotfiles_repo::is_origin_main_known "${git_dir}"; then
    if ! run_mut git --git-dir="${git_dir}" fetch -q origin; then
      log::err "fetch failed; origin/main stays unknown | url='$(dotfiles_repo::origin_url "${git_dir}")'"
      return 1
    fi
  fi
}
