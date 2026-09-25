# step dotfiles_jobs — the one launchd job of the dotfiles jobs framework (screen unlock, login,
# every 5 minutes); it runs the job plugins of both tiers, git-health's hourly tick among them.
step::declare dotfiles_jobs --group repo --needs dotfiles_repo \
  --desc "dotfiles jobs launchd job (runs the job plugins of both tiers) installed and loaded"

check::dotfiles_jobs() {
  local label="com.$(id -un).dotfiles-jobs" plist="${ARI_DOTFILES_LAUNCH_AGENTS_DIR}/com.$(id -un).dotfiles-jobs.plist"
  if [[ ! -f "${plist}" ]]; then
    verdict fail not_installed -d "plist missing | path='${plist}'" -f "${CLI_NAME} apply dotfiles_jobs"
    return 0
  fi
  if ! plutil -lint -s "${plist}" >/dev/null 2>&1; then
    verdict fail not_installed -d "plist does not lint | path='${plist}'" -f "${CLI_NAME} apply dotfiles_jobs"
    return 0
  fi
  if ! launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1; then
    verdict fail not_loaded -d "job not loaded | label='${label}'" -f "${CLI_NAME} apply dotfiles_jobs"
    return 0
  fi
  verdict ok loaded -d "label='${label}'"
}

# jobs_install lives with the jobs verb; it is idempotent and dry-run aware itself.
apply::dotfiles_jobs() {
  need_lib "${ARI_DOTFILES_CMD}/jobs.zsh" || return 3
  jobs_install
}
