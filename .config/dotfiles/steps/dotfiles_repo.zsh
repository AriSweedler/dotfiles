# step dotfiles_repo — the shared tier: bare repo cloned, HOME checked out, hooks wired,
# submodules initialized, nothing dirty.
step::declare dotfiles_repo --group repo \
  --desc "shared dotfiles bare repo cloned, checked out into HOME, hooks wired"

check::dotfiles_repo() {
  local git_dir="${NEW_MACHINE_DF_GIT_DIR}"
  if [[ ! -d "${git_dir}" ]]; then
    verdict fail missing_bare_repo -d "no bare repo | git_dir='${git_dir}' remote='${DOTFILES_REMOTE}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if ! git --git-dir="${git_dir}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    verdict fail missing_bare_repo -d "repo has no HEAD | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if tier::is_worktree_unpopulated "${git_dir}" "${HOME}" \
     && [[ -n "$(git --git-dir="${git_dir}" ls-tree -r --name-only HEAD 2>/dev/null | head -n 1)" ]]; then
    verdict fail not_checked_out -d "bare repo exists but HOME was never checked out | git_dir='${git_dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  local hooks
  hooks="$(tier::hooks_path "${git_dir}")"
  if [[ "${hooks}" != "${NEW_MACHINE_DF_HOOKS}" ]]; then
    verdict fail hooks_path -d "core.hooksPath='${hooks}' expected='${NEW_MACHINE_DF_HOOKS}'" -f "${CLI_NAME} apply dotfiles_repo"
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
  local dirty
  dirty="$(git --git-dir="${git_dir}" --work-tree="${HOME}" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "${dirty}" ]]; then
    local -a lines=("${(f)dirty}")
    verdict warn uncommitted -d "$(plural "${#lines}" 'uncommitted file' 'uncommitted files')" -f "git df status"
    return 0
  fi
  verdict ok clean -d "git_dir='${git_dir}' hooks='${hooks}'"
}

# Populates HOME from the bare clone. Fails, listing the conflicting files in the log, when HOME
# already holds files the checkout would overwrite; nothing is moved or deleted on the user's behalf.
apply::dotfiles_repo() {
  local git_dir="${NEW_MACHINE_DF_GIT_DIR}"
  if [[ ! -d "${git_dir}" ]]; then
    run_mut git clone --bare "${DOTFILES_REMOTE}" "${git_dir}" || return 1
  fi
  if tier::is_worktree_unpopulated "${git_dir}" "${HOME}"; then
    if ! run_mut git --git-dir="${git_dir}" --work-tree="${HOME}" checkout; then
      log::err "checkout failed; move the listed files aside and re-run | work_tree='${HOME}'"
      return 1
    fi
  fi
  # Everything after the checkout is the dotfiles harness's job: tracking config, hooks for
  # both tiers, submodules, skill links, the ssh key. It ships in the checkout just made.
  local harness="${HOME}/.config/bin/dotfiles"
  if [[ ! -r "${harness}" ]] && ! is_dry_run; then
    log::err "dotfiles harness missing after checkout | path='${harness}'"
    return 1
  fi
  run_mut zsh "${harness}" init
}
