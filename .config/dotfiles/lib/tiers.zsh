# dotfiles/lib/tiers.zsh — git for the two tiers and the submodules: which repo, its hooks, its
# checkout, its identity, and the one commit routine the brew model uses.
#
#   shared  ~/dotfiles.git              work tree $HOME         committed here, pushed by `dotfiles push`
#   local   ~/.local/local-dotfiles.git work tree $HOME/.local  committed and pushed
#
# Explicit --git-dir/--work-tree throughout: the `git df`/`git ldf` aliases sit behind a config
# include a half-bootstrapped machine may lack, and the fake-HOME tests have no aliases at all.

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
is_repo_present() { [[ -e "${TIER_GIT_DIR[${1}]:-${HOME}/${1}/.git}" ]]; }
# A repo's push log: shared.log, local.log, or the path minus its leading dot, slashes as dashes.
log_file() { print -r -- "${LOG_DIR}/${${1#.}//\//-}.log"; }

# The brew model still says `global` for the shared tier.
tier::name() {
  case "${1}" in
    global|shared) print -r -- shared ;;
    local) print -r -- local ;;
    *) print -u2 "tier::name: bad tier '${1}'"; return 64 ;;
  esac
}
tier::is_tier() { [[ "${1}" == (global|shared|local) ]]; }
# git for one tier by name, e.g. `tier::git local status --porcelain`.
tier::git() {
  local tier; tier="$(tier::name "${1}")" || return 64; shift
  git --git-dir="${TIER_GIT_DIR[${tier}]}" --work-tree="${TIER_WORK_TREE[${tier}]}" "$@"
}

# The rules of an ignore or exclude file: comments and blank lines dropped, so two files that
# differ only in commentary compare equal.
exclude_rules() {
  grep -vE '^[[:space:]]*(#|$)' "${1}" || true
}

# core.hooksPath is repo-local, so hooks versioned in the dotfiles tree must be wired on every machine.
tier::hooks_path() {
  git --git-dir="${1}" config --local --get core.hooksPath 2>/dev/null || true
}

tier::ensure_hooks_path() {
  local git_dir="${1}" hooks_dir="${2}"
  if [[ ! -d "${git_dir}" ]] && is_dry_run; then
    run_mut git --git-dir="${git_dir}" config --local core.hooksPath "${hooks_dir}"
    return 0
  fi
  if [[ "$(tier::hooks_path "${git_dir}")" == "${hooks_dir}" ]]; then
    log::info "hooks wired | git_dir='${git_dir}' hooks_dir='${hooks_dir}'"
    return 0
  fi
  run_mut git --git-dir="${git_dir}" config --local core.hooksPath "${hooks_dir}"
}

# A bare clone has no index, so ls-files is empty until the first checkout populates it.
# ls-files lists only the paths under the cwd, so it runs from the work-tree root: a check
# started from a subdirectory of HOME (or from another repo inside it) must not read a populated
# index as empty.
tier::is_worktree_unpopulated() {
  local git_dir="${1}" work_tree="${2}"
  [[ -d "${git_dir}" ]] || return 0
  [[ -z "$(git -C "${work_tree}" --git-dir="${git_dir}" --work-tree="${work_tree}" ls-files 2>/dev/null | head -n 1)" ]]
}

# --- Submodule identity: local config is not cloned, so each submodule's apply pins it ---
tier::is_submodule_identity_ok() {
  local dir="${1}"
  [[ "$(git -C "${dir}" config --local user.name 2>/dev/null)" == "${SUBMODULE_GIT_NAME}" ]] &&
    [[ "$(git -C "${dir}" config --local user.email 2>/dev/null)" == "${SUBMODULE_GIT_EMAIL}" ]]
}
tier::submodule_identity_apply() {
  local dir="${1}"
  tier::is_submodule_identity_ok "${dir}" && return 0
  run_mut git -C "${dir}" config user.name "${SUBMODULE_GIT_NAME}" || return 1
  run_mut git -C "${dir}" config user.email "${SUBMODULE_GIT_EMAIL}"
}

# --- Committing to a tier (the brew model's decree/undecree) ---
tier::is_no_push() {
  case "${DOTFILES_NO_PUSH:-0}" in 0|false|no|"") return 1 ;; esac
  return 0
}

# tier::index_clean <tier>: 0 when the tier can take a commit of exactly the paths a caller is
# about to add. Callers that edit files before committing run this first so a refusal leaves the
# work tree untouched. Returns 1 (logged) when the bare repo is missing or the index already
# holds unrelated changes.
tier::index_clean() {
  local tier; tier="$(tier::name "${1}")" || return 64
  local git_dir="${TIER_GIT_DIR[${tier}]}"
  if [[ ! -d "${git_dir}" ]]; then
    log::err "bare repo missing | tier='${tier}' git_dir='${git_dir}' fix='${CLI_NAME} apply dotfiles_repo|local_dotfiles_repo'"
    return 1
  fi
  if ! tier::git "${tier}" diff --cached --quiet; then
    log::err "unrelated staged changes; commit or unstage first | tier='${tier}' git_dir='${git_dir}'"
    log::ERR "$(tier::git "${tier}" diff --cached --name-only)"
    return 1
  fi
  return 0
}

# tier::commit <tier> <message> <abs path>...
#
# Refuses when the index already holds unrelated changes, so the commit contains exactly the
# given paths. Hooks run normally; a rejection leaves the files edited but uncommitted and is
# reported verbatim. The local tier pushes unless DOTFILES_NO_PUSH; a failed push is a warning,
# not an error, because the weekly local_dotfiles_repo check surfaces unpushed commits later.
# Returns 0 committed, 1 refused or rejected, 64 usage.
tier::commit() {
  local given_tier="${1:-}" message="${2:-}"
  shift 2 2>/dev/null || { print -u2 "usage: tier::commit <shared|local> <message> <abs path>..."; return 64; }
  local -a paths=("$@")
  local tier
  if ! tier="$(tier::name "${given_tier}")" || [[ -z "${message}" ]] || (( ${#paths} == 0 )); then
    print -u2 "usage: tier::commit <shared|local> <message> <abs path>..."
    return 64
  fi
  local given
  for given in "${paths[@]}"; do
    if [[ "${given}" != /* ]]; then
      log::err "tier::commit needs absolute paths | path='${given}'"
      return 64
    fi
  done
  local git_text="git --git-dir=${TIER_GIT_DIR[${tier}]} --work-tree=${TIER_WORK_TREE[${tier}]}"
  if is_dry_run; then
    print -r -- "would run: ${git_text} add -- ${(j: :)paths}"
    print -r -- "would run: ${git_text} commit -m '${message%%$'\n'*}'"
    if [[ "${tier}" == local ]] && ! tier::is_no_push; then
      print -r -- "would run: ${git_text} push"
    fi
    return 0
  fi
  tier::index_clean "${tier}" || return 1
  local out rc=0
  out="$(tier::git "${tier}" add -- "${paths[@]}" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    log::err "git add failed | tier='${tier}' rc='${rc}'"
    log::ERR "${out}"
    return 1
  fi
  rc=0
  out="$(tier::git "${tier}" commit -m "${message}" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    log::err "commit rejected; files are edited but uncommitted | tier='${tier}' rc='${rc}'"
    log::ERR "${out}"
    return 1
  fi
  # The brew model's callers and their tests know the shared tier as `global`.
  print -r -- "[${given_tier}] $(tier::git "${tier}" log --oneline -1)"
  case "${tier}" in
    shared)
      print -r -- 'Run `dotfiles push` when ready.'
      ;;
    local)
      if tier::is_no_push; then
        log::info "push skipped | tier='local' fix='git ldf push'"
        return 0
      fi
      rc=0
      out="$(tier::git "${tier}" push 2>&1)" || rc=$?
      # git reports a failing pre-push hook as exit 1, same as being offline; the
      # chrome-exoskeleton hook prints a verdict line so this can tell them apart.
      if [[ "${out}" == *'[EXO-PREPUSH] failed'* ]]; then
        log::err "pre-push checks failed; nothing pushed | tier='local' fix='exo check, then git ldf push'"
        log::ERR "${out}"
        return 1
      fi
      if (( rc != 0 )); then
        log::warn "push failed; run 'git ldf push' when online"
        log::WARN "${out}"
        return 0
      fi
      log::info "pushed | tier='local'"
      ;;
  esac
  return 0
}
