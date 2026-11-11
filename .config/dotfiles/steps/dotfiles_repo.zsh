# step dotfiles_repo — the shared tier: the plain clone ~/dotfiles (home-manager links its files
# into HOME), or the bare repo ~/dotfiles.git with HOME checked out (renamed from the pre-harness
# bare ~/dotfiles); either tracking origin, hooks wired, every dev repo (dev-repos: Ari's own
# repos, read by the shared flake as inputs) cloned in place, origin/main known, every checked-out
# dev repo documented (README.md and its linked skill),
# nothing dirty. Every fix but the docs (a human writes them) is idempotent: `dotfiles init`
# runs this after every pull.
step::declare dotfiles_repo --group repo \
  --desc "shared dotfiles repo cloned (the ~/dotfiles clone, or the legacy bare repo checked out into HOME), tracking origin, hooks wired" \
  --apply "clones the bare repo (or renames the legacy one), sets its tracking config, checks it out into HOME, wires the hooks, clones each missing dev repo (a submodule checkout becomes a plain clone) and fetches origin"
step::watches dotfiles_repo '.config/dotfiles/dev-repos' '.config/git/dotfiles-hooks/**'

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
# One line per dev repo, '<state> <path>': '-' not cloned, 's' still a submodule checkout (its .git
# a file into the shared repo's modules/), '+' its HEAD is not the commit the committed flake.lock
# pins, ' ' at it. Stat checks and one rev-parse each.
dotfiles_repo::dev_status() {
  local work_tree="${ARI_DOTFILES_DF_WORK_TREE}" sub rev head
  local -A locked=()
  while IFS=$'\t' read -r sub rev; do locked[${sub}]="${rev}"; done < <(tier::locked_revs "${SUBMODULES[@]}")
  for sub in "${SUBMODULES[@]}"; do
    if [[ ! -e "${work_tree}/${sub}/.git" ]]; then print -r -- "- ${sub}"; continue; fi
    if [[ -f "${work_tree}/${sub}/.git" ]]; then print -r -- "s ${sub}"; continue; fi
    head="$(git -C "${work_tree}/${sub}" rev-parse -q --verify HEAD 2>/dev/null || true)"
    if [[ -n "${locked[${sub}]:-}" && "${head}" != "${locked[${sub}]}" ]]; then print -r -- "+ ${sub}"; else print -r -- "  ${sub}"; fi
  done
}

# A submodule checkout becomes a plain clone in place: its git dir moves out of the shared repo's
# modules/ into <path>/.git, core.worktree goes, and the shared repo forgets the submodule.
dotfiles_repo::unsubmodule() {
  local git_dir="${1}" dir="${2}" name="${3}" moddir
  moddir="$(git -C "${dir}" rev-parse --absolute-git-dir 2>/dev/null)" || { log::err "not a git checkout | path='${dir}'"; return 1; }
  run_mut git --git-dir="${moddir}" config --unset core.worktree || true
  run_mut rm "${dir}/.git" || return 1
  run_mut mv "${moddir}" "${dir}/.git" || return 1
  run_mut git --git-dir="${git_dir}" config --remove-section "submodule.${name}" 2>/dev/null || true
  # A submodule sits detached; a plain clone works on main. Only when that loses nothing: main
  # absent or at HEAD.
  local head main
  head="$(git -C "${dir}" rev-parse -q --verify HEAD 2>/dev/null || true)"
  main="$(git -C "${dir}" rev-parse -q --verify refs/heads/main 2>/dev/null || true)"
  if [[ -z "$(git -C "${dir}" branch --show-current 2>/dev/null)" && ( -z "${main}" || "${main}" == "${head}" ) ]]; then
    run_mut git -C "${dir}" switch -q -C main || return 1
    git -C "${dir}" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 \
      && run_mut git -C "${dir}" branch -q --set-upstream-to=origin/main main
  fi
  return 0
}

# A checked-out submodule is documented when it has README.md and its skill,
# skills/ari-dotfile--submodule-<name>/SKILL.md, linked into ~/.claude/skills. Walks env.zsh's
# SUBMODULES (one not checked out is submodule_uninitialized's); prints '<fix>\t<what lacks
# what>' per gap, first gap first. Stat checks only: nothing is exec'd.
dotfiles_repo::undocumented() {
  local sub name dir skill link recipe='/ari-dotfile--submodule § Creating one'
  for sub in "${SUBMODULES[@]}"; do
    dir="${ARI_DOTFILES_DF_WORK_TREE}/${sub}" name="${sub:t}"
    [[ -e "${dir}/.git" ]] || continue
    skill="${dir}/skills/ari-dotfile--submodule-${name}/SKILL.md"
    link="${HOME}/.claude/skills/ari-dotfile--submodule-${name}"
    [[ -f "${dir}/README.md" ]] \
      || print -r -- "write ~/${sub}/README.md (${recipe}, step 1)"$'\t'"${sub} lacks README.md"
    if [[ ! -f "${skill}" ]]; then
      print -r -- "write ~/${sub}/skills/ari-dotfile--submodule-${name}/SKILL.md (${recipe}, step 5)"$'\t'"${sub} lacks skills/ari-dotfile--submodule-${name}/SKILL.md"
    elif [[ ! -e "${link}" || "${link:A}" != "${skill:h:A}" ]]; then
      print -r -- "zsh \$HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link --execute (/ari-dotfile--submodule § Layout contract)"$'\t'"~/.claude/skills lacks ari-dotfile--submodule-${name} linked to ~/${sub}/skills/ari-dotfile--submodule-${name}"
    fi
  done
  return 0
}

check::dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_DF_GIT_DIR}" work_tree="${ARI_DOTFILES_DF_WORK_TREE}" legacy="${LEGACY_SHARED_GIT_DIR}"
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
  # The slow read (status about 40 ms) starts now, side by side with the config checks below.
  local -i dirty_fd
  exec {dirty_fd}< <(git --git-dir="${git_dir}" --work-tree="${work_tree}" status --porcelain --untracked-files=no 2>/dev/null || true)
  local -a missing=("${(@f)$(dotfiles_repo::tracking_missing "${git_dir}")}")
  missing=("${(@)missing:#}")
  if (( ${#missing} )); then
    verdict fail tracking -d "tracking config missing | keys='${(j:, :)${(@)missing%%=*}}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if tier::is_worktree_unpopulated "${git_dir}" "${work_tree}" \
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
  if (( ${#SUBMODULES} )); then
    local dev_status uninit layout drifted
    dev_status="$(dotfiles_repo::dev_status)"
    uninit="$(print -r -- "${dev_status}" | awk '/^-/ {print $2}')"
    layout="$(print -r -- "${dev_status}" | awk '/^s/ {print $2}')"
    drifted="$(print -r -- "${dev_status}" | awk '/^\+/ {print $2}')"
    if [[ -n "${uninit}" ]]; then
      verdict fail submodule_uninitialized -d "dev repo not cloned | paths='${uninit//$'\n'/, }'" -f "${CLI_NAME} apply dotfiles_repo"
      return 0
    fi
    if [[ -n "${layout}" ]]; then
      verdict fail submodule_layout -d "still a git submodule checkout; the shared flake reads it as an input now | paths='${layout//$'\n'/, }'" -f "${CLI_NAME} apply dotfiles_repo"
      return 0
    fi
    local -a undocumented=("${(@f)$(dotfiles_repo::undocumented)}")
    undocumented=("${(@)undocumented:#}")
    if (( ${#undocumented} )); then
      verdict fail submodule_undocumented -m -d "${(j:; :)${(@)undocumented#*$'\t'}}" -f "${undocumented[1]%%$'\t'*}"
      return 0
    fi
    if [[ -n "${drifted}" ]]; then
      verdict warn submodule_drift -d "checkout differs from the commit flake.lock pins | paths='${drifted//$'\n'/, }'" -f "${CLI_NAME} push   (it bumps the lock after pushing the repo)"
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
# checkout, hooks, the dev repos, the first fetch. The checkout fails, listing the conflicting files
# in the log, when HOME already holds files it would overwrite; nothing is moved on the user's behalf.
apply::dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_DF_GIT_DIR}" work_tree="${ARI_DOTFILES_DF_WORK_TREE}" legacy="${LEGACY_SHARED_GIT_DIR}" kv
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
  if tier::is_worktree_unpopulated "${git_dir}" "${work_tree}"; then
    if ! run_mut git --git-dir="${git_dir}" --work-tree="${work_tree}" checkout; then
      log::err "checkout failed; move the listed files aside and re-run | work_tree='${work_tree}'"
      return 1
    fi
  fi
  tier::ensure_hooks_path "${git_dir}" "${ARI_DOTFILES_DF_HOOKS}" || return 1
  tier::submodule_identity_apply "${git_dir}" || return 1
  # The manifest came with the checkout above: read it again. Each dev repo is cloned when missing
  # and converted when still a submodule checkout; one already cloned is left on its branch.
  dev_repos::load
  local sub dir
  for sub in "${SUBMODULES[@]}"; do
    dir="${work_tree}/${sub}"
    if [[ -f "${dir}/.git" ]]; then
      dotfiles_repo::unsubmodule "${git_dir}" "${dir}" "${sub}" || return 1
    elif [[ ! -e "${dir}/.git" ]]; then
      if [[ -z "${SUBMODULE_URL[${sub}]}" ]]; then log::err "dev repo has no url | path='${sub}' file='${DEV_REPOS}'"; return 1; fi
      run_mut git clone -q "${SUBMODULE_URL[${sub}]}" "${dir}" || return 1
    fi
  done
  if dotfiles_repo::has_origin "${git_dir}" && ! dotfiles_repo::is_origin_main_known "${git_dir}"; then
    if ! run_mut git --git-dir="${git_dir}" fetch -q origin; then
      log::err "fetch failed; origin/main stays unknown | url='$(dotfiles_repo::origin_url "${git_dir}")'"
      return 1
    fi
  fi
}
