# dotfiles/lib/repos.zsh — git for a repo: the tiers by name, a submodule by path.

# --- Repos and helpers ---

#######################################
# git for a repo. -C <worktree> as well as --git-dir/--work-tree: ls-files, status and
# submodule scope themselves to the cwd otherwise.
# Arguments:
#   $1 - repo: 'shared', 'local', or a submodule path relative to $HOME
#   $@ - git arguments
#######################################
repo_git() {
  local repo="${1}"; shift
  if [[ -z "${TIER_GIT_DIR[${repo}]:-}" ]]; then git -C "${HOME}/${repo}" "${@}"; return; fi
  git -C "${TIER_WORK_TREE[${repo}]}" --git-dir="${TIER_GIT_DIR[${repo}]}" --work-tree="${TIER_WORK_TREE[${repo}]}" "${@}"
}
# True (0) when the repo exists here: the tier's bare repo, or the submodule's checkout (its .git is a file).
repo_present() { [[ -e "${TIER_GIT_DIR[${1}]:-${HOME}/${1}/.git}" ]]; }
# A repo's push log: shared.log, local.log, or the path minus its leading dot, slashes as dashes.
log_file() { print -r -- "${LOG_DIR}/${${1#.}//\//-}.log"; }
