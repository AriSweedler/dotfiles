# step dotfiles_repo — the shared tier: bare repo at ~/dotfiles.git (renamed from the pre-harness
# ~/dotfiles), tracking origin, HOME checked out, hooks wired, submodules initialized,
# origin/main known, every checked-out submodule documented (README.md and its linked skill),
# nothing dirty. Every fix but the docs (a human writes them) is idempotent: `dotfiles init`
# runs this after every pull.
step::declare dotfiles_repo --group repo \
  --desc "shared dotfiles bare repo cloned, tracking origin, checked out into HOME, hooks wired" \
  --apply "clones the bare repo (or renames the legacy one), sets its tracking config, checks it out into HOME, wires the hooks, initializes new submodules and fetches origin"
step::watches dotfiles_repo '.gitmodules' '.config/git/dotfiles-hooks/**'

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

# A checked-out submodule is documented when it has README.md and its skill,
# skills/ari-dotfile--submodule-<name>/SKILL.md, linked into ~/.claude/skills. Walks env.zsh's
# SUBMODULES (one not checked out is submodule_uninitialized's); prints '<fix>\t<what lacks
# what>' per gap, first gap first. Stat checks only: nothing is exec'd.
dotfiles_repo::undocumented() {
  local sub name dir skill link recipe='/ari-dotfile--submodule § Creating one'
  for sub in "${SUBMODULES[@]}"; do
    dir="${HOME}/${sub}" name="${sub:t}"
    [[ -e "${dir}/.git" ]] || continue
    skill="${dir}/skills/ari-dotfile--submodule-${name}/SKILL.md"
    link="${HOME}/.claude/skills/ari-dotfile--submodule-${name}"
    [[ -f "${dir}/README.md" ]] \
      || print -r -- "write ~/${sub}/README.md (${recipe}, step 1)"$'\t'"${sub} lacks README.md"
    if [[ ! -f "${skill}" ]]; then
      print -r -- "write ~/${sub}/skills/ari-dotfile--submodule-${name}/SKILL.md (${recipe}, step 5)"$'\t'"${sub} lacks skills/ari-dotfile--submodule-${name}/SKILL.md"
    elif [[ ! -e "${link}" || "${link:A}" != "${skill:h:A}" ]]; then
      print -r -- "zsh \$HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link (/ari-dotfile--submodule § Layout contract)"$'\t'"~/.claude/skills lacks ari-dotfile--submodule-${name} linked to ~/${sub}/skills/ari-dotfile--submodule-${name}"
    fi
  done
  return 0
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
  # The two slow reads (submodule status about 180 ms, status about 40 ms) start now, side by side
  # with the config checks below, and are read where the verdict needs them. Both only read;
  # status may refresh the index under an optional lock, so submodule status runs with optional
  # locks off and the two never contend for index.lock.
  local -i sub_fd=-1 dirty_fd
  if [[ -f "${HOME}/.gitmodules" ]]; then
    exec {sub_fd}< <(GIT_OPTIONAL_LOCKS=0 git -C "${HOME}" --git-dir="${git_dir}" --work-tree="${HOME}" submodule status 2>/dev/null || true)
  fi
  exec {dirty_fd}< <(git --git-dir="${git_dir}" --work-tree="${HOME}" status --porcelain --untracked-files=no 2>/dev/null || true)
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
  # The repo is public; an identity inherited from an include under HOME would publish it.
  if ! tier::is_submodule_identity_ok "${git_dir}"; then
    verdict fail identity_drift -d "local user.name/user.email are not the personal identity | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if (( sub_fd >= 0 )); then
    local sub_status uninit drifted
    IFS= read -r -d '' -u "${sub_fd}" sub_status || true
    while [[ "${sub_status}" == *$'\n' ]]; do sub_status="${sub_status%$'\n'}"; done
    uninit="$(print -r -- "${sub_status}" | awk '/^-/ {print $2}')"
    drifted="$(print -r -- "${sub_status}" | awk '/^\+/ {print $2}')"
    if [[ -n "${uninit}" ]]; then
      verdict fail submodule_uninitialized -d "submodule not checked out | paths='${uninit//$'\n'/, }'" -f "${CLI_NAME} apply dotfiles_repo"
      return 0
    fi
    local -a undocumented=("${(@f)$(dotfiles_repo::undocumented)}")
    undocumented=("${(@)undocumented:#}")
    if (( ${#undocumented} )); then
      verdict fail submodule_undocumented -m -d "${(j:; :)${(@)undocumented#*$'\t'}}" -f "${undocumented[1]%%$'\t'*}"
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
  IFS= read -r -d '' -u "${dirty_fd}" dirty || true
  while [[ "${dirty}" == *$'\n' ]]; do dirty="${dirty%$'\n'}"; done
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
  tier::submodule_identity_apply "${git_dir}" || return 1
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
