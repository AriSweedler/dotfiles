# step local_dotfiles_repo — the local tier: a bare repo with the allowlist as info/exclude,
# hooks wired, a remote, nothing unpushed.
step::declare local_dotfiles_repo --group repo \
  --desc "local dotfiles bare repo exists with the allowlist, hooks, and a remote"

check::local_dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_LDF_GIT_DIR}" exclude="${ARI_DOTFILES_LDF_GIT_DIR}/info/exclude"
  if [[ ! -d "${git_dir}" ]]; then
    verdict fail missing_bare_repo -d "no bare repo | git_dir='${git_dir}'" -f "${CLI_NAME} apply local_dotfiles_repo"
    return 0
  fi
  if [[ ! -r "${LDF_EXCLUDE_TEMPLATE}" ]]; then
    verdict error template_missing -d "allowlist template missing | path='${LDF_EXCLUDE_TEMPLATE}'"
    return 0
  fi
  local current_rules=""
  if [[ -f "${exclude}" ]]; then
    current_rules="$(exclude_rules "${exclude}")"
  fi
  if [[ -z "${current_rules}" ]]; then
    verdict fail allowlist_missing -d "info/exclude has no rules | exclude='${exclude}'" -f "${CLI_NAME} apply local_dotfiles_repo"
    return 0
  fi
  local hooks
  hooks="$(tier::hooks_path "${git_dir}")"
  if [[ "${hooks}" != "${ARI_DOTFILES_LDF_HOOKS}" ]]; then
    verdict fail hooks_path -d "core.hooksPath='${hooks}' expected='${ARI_DOTFILES_LDF_HOOKS}'" -f "${CLI_NAME} apply local_dotfiles_repo"
    return 0
  fi
  # The machine keeps its own allowlist; the tool only points at the difference.
  if [[ "${current_rules}" != "$(exclude_rules "${LDF_EXCLUDE_TEMPLATE}")" ]]; then
    verdict warn allowlist_differs -m -d "info/exclude rules differ from the template" -f "diff ${exclude} ${LDF_EXCLUDE_TEMPLATE}"
    return 0
  fi
  local origin
  origin="$(git --git-dir="${git_dir}" remote get-url origin 2>/dev/null || true)"
  if [[ -z "${origin}" ]]; then
    verdict warn no_remote -m -f "git ldf remote add origin <this machine's private repo>" \
      -d $'the local-dotfiles remote is one private repo per machine:\n  git ldf remote add origin <this machine\'s private repo>\n  git ldf push --set-upstream origin main   # after the first commit'
    return 0
  fi
  # No fetch: origin/main is whatever the last push left behind; before the first push every commit is unpushed.
  local -i unpushed=0
  if git --git-dir="${git_dir}" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    unpushed=$(git --git-dir="${git_dir}" rev-list --count origin/main..HEAD 2>/dev/null || print 0)
  elif git --git-dir="${git_dir}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    unpushed=$(git --git-dir="${git_dir}" rev-list --count HEAD 2>/dev/null || print 0)
  fi
  if (( unpushed > 0 )); then
    verdict warn unpushed -d "$(plural "${unpushed}" 'unpushed commit' 'unpushed commits')" -f "git ldf push"
    return 0
  fi
  verdict ok configured -d "git_dir='${git_dir}' origin='${origin}'"
}

# info/exclude is the allowlist that makes `git ldf add -A` safe. Installed from the versioned
# template over git's stock (comment-only) file; a machine whose rules differ keeps its copy.
apply::local_dotfiles_repo() {
  local git_dir="${ARI_DOTFILES_LDF_GIT_DIR}" exclude="${ARI_DOTFILES_LDF_GIT_DIR}/info/exclude"
  if [[ ! -d "${git_dir}" ]]; then
    run_mut git init --bare "${git_dir}" || return 1
  fi
  if [[ ! -r "${LDF_EXCLUDE_TEMPLATE}" ]]; then
    log::err "allowlist template missing | path='${LDF_EXCLUDE_TEMPLATE}'"
    return 1
  fi
  local rc=0
  if [[ ! -f "${exclude}" || -z "$(exclude_rules "${exclude}")" ]]; then
    run_mut mkdir -p "${exclude:h}" || rc=1
    run_mut cp "${LDF_EXCLUDE_TEMPLATE}" "${exclude}" || rc=1
  fi
  tier::ensure_hooks_path "${git_dir}" "${ARI_DOTFILES_LDF_HOOKS}" || rc=1
  return "${rc}"
}
