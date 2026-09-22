# dotfiles/lib/init.zsh — `dotfiles init` and `dotfiles pull`: every step idempotent.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

# --- init: every step idempotent; a shared repo still missing (a dry-run clone) skips its steps ---

#######################################
# Rename the shared bare repo from its pre-harness name, once, and move on: the rest of init
# gives the renamed repo its tracking config, hooks and checkout like any other. A directory
# at the old name that is not a bare repo (no HEAD, or a .git inside) is someone else's and is
# left alone with a warning; both names present is a conflict only a human can settle.
#######################################
init_migrate() {
  local old="${LEGACY_SHARED_GIT_DIR}" new="${TIER_GIT_DIR[shared]}"
  [[ -d "${old}" ]] || return 0
  if [[ ! -f "${old}/HEAD" || -d "${old}/.git" ]]; then
    log::warn "legacy path is not a bare repo; leaving it alone | path='${old}'"; return 0
  fi
  if [[ -e "${new}" ]]; then
    log::err "legacy and current bare repo both exist; keep one | legacy='${old}' current='${new}'"; return 1
  fi
  run_mut mv "${old}" "${new}" || return 1
  [[ "${DRY_RUN}" == true ]] || log::info "migrated shared bare repo | from='${old}' to='${new}'"
}

init_clone() {
  if repo_present shared; then log::info "shared repo present | git_dir='${TIER_GIT_DIR[shared]}'"; return 0; fi
  run_mut git clone --bare "${DOTFILES_REMOTE}" "${TIER_GIT_DIR[shared]}"
}

#######################################
# A bare clone has no tracking config: no fetch refspec (so no remote-tracking refs) and no
# upstream for main. pull needs the upstream; status needs origin/main for ahead/behind.
# Each key is set only when it differs.
#######################################
init_tracking() {
  repo_present shared || return 0
  local kv changed=false
  for kv in 'remote.origin.fetch=+refs/heads/*:refs/remotes/origin/*' 'branch.main.remote=origin' 'branch.main.merge=refs/heads/main'; do
    [[ "$(repo_git shared config "${kv%%=*}" 2>/dev/null || true)" == "${kv#*=}" ]] && continue
    run_mut repo_git shared config "${kv%%=*}" "${kv#*=}" || return 1
    changed=true
  done
  [[ "${changed}" == true ]] || log::info "main tracks origin/main | git_dir='${TIER_GIT_DIR[shared]}'"
}

# Check the shared repo out into $HOME when nothing is checked out yet (one index lookup: this script is tracked).
init_checkout() {
  repo_present shared || return 0
  if [[ -n "$(repo_git shared ls-files -- .config/bin/dotfiles 2>/dev/null)" ]]; then
    log::info "shared tier checked out | work_tree='${TIER_WORK_TREE[shared]}'"; return 0
  fi
  if ! run_mut repo_git shared checkout; then
    log::err "checkout failed; move the listed files aside and re-run | work_tree='${TIER_WORK_TREE[shared]}'"; return 1
  fi
}

# Point a tier's core.hooksPath at its versioned hooks dir, once.
init_hooks() {
  local repo="${1}" hooks_dir="${TIER_HOOKS[${1}]}"
  if [[ "$(repo_git "${repo}" config --local core.hooksPath 2>/dev/null || true)" == "${hooks_dir}" ]]; then
    log::info "hooks wired | tier='${TIER_ALIAS[${repo}]}' hooks_dir='${hooks_dir}'"; return 0
  fi
  run_mut repo_git "${repo}" config --local core.hooksPath "${hooks_dir}"
}

#######################################
# Check out the submodules never initialized here. An initialized one is left alone:
# `submodule update` would detach it onto the pointer, and a checkout ahead of the pointer
# is a commit awaiting its bump, not drift to undo (pull moves pointers; status shows drift).
#######################################
init_submodules() {
  local repo
  local -a missing=()
  for repo in "${SUBMODULES[@]}"; do repo_present "${repo}" || missing+=("${repo}"); done
  if (( ${#missing} == 0 )); then log::info "submodules checked out | count='${#SUBMODULES}'"; return 0; fi
  # git submodule refuses to run outside the worktree.
  ( cd "${TIER_WORK_TREE[shared]}" && run_mut repo_git shared submodule update --init -- "${missing[@]}" )
}

# The registry prints its linked/pruned/skipped summary on stdout; log it.
init_skills() {
  if [[ ! -r "${REGISTRY_LINK}" ]]; then log::warn "skill registry not found; skills not linked | path='${REGISTRY_LINK}'"; return 0; fi
  runner=run_cmd_cap run_mut zsh "${REGISTRY_LINK}" --prune
}

# True (0) when the agent already holds the key at the given path.
ssh_key_loaded() {
  local fingerprint
  fingerprint="$(ssh-keygen -lf "${1}" 2>/dev/null | awk '{print $2}')" || return 1
  [[ -n "${fingerprint}" ]] && ssh-add -l 2>/dev/null | awk '{print $2}' | grep -qxF "${fingerprint}"
}

#######################################
# Load the GitHub ssh key into the agent, its path and passphrase read from the 1Password
# item the local tier names. The passphrase goes from op straight to ssh-add through an
# askpass helper: never the clipboard, never argv.
#######################################
init_ssh_key() {
  if [[ -z "${DOTFILES_SSH_KEY_OP_ITEM}" ]]; then log::info "no ssh key configured; skipping | hint='DOTFILES_SSH_KEY_OP_ITEM in the local tier'"; return 0; fi
  local key_path="${DOTFILES_SSH_KEY_PATH/#\~/${HOME}}" askpass
  local -a vault_flag=()
  [[ -n "${DOTFILES_SSH_KEY_OP_VAULT}" ]] && vault_flag=(--vault "${DOTFILES_SSH_KEY_OP_VAULT}")
  # The common case, settled without 1Password: path known, key already loaded.
  if [[ -n "${key_path}" ]] && ssh_key_loaded "${key_path}"; then log::info "ssh key already in the agent | path='${key_path}'"; return 0; fi
  if ! command -v op >/dev/null 2>&1; then log::warn "1Password CLI missing; ssh key not loaded | fix='brew install 1password-cli'"; return 0; fi
  if [[ -z "${key_path}" ]]; then
    if ! key_path="$(op item get "${DOTFILES_SSH_KEY_OP_ITEM}" "${vault_flag[@]}" --field "Absolute path" 2>/dev/null)"; then
      log::err "1Password item not readable | item='${DOTFILES_SSH_KEY_OP_ITEM}' vault='${DOTFILES_SSH_KEY_OP_VAULT}' fix='op signin'"; return 1
    fi
    key_path="${key_path/#\~/${HOME}}"
  fi
  if [[ ! -f "${key_path}" ]]; then log::err "ssh key file missing | path='${key_path}' item='${DOTFILES_SSH_KEY_OP_ITEM}'"; return 1; fi
  if ssh_key_loaded "${key_path}"; then log::info "ssh key already in the agent | path='${key_path}'"; return 0; fi
  if [[ "${DRY_RUN}" == true ]]; then log::info "dry-run, would ssh-add with the passphrase from 1Password | path='${key_path}' item='${DOTFILES_SSH_KEY_OP_ITEM}'"; return 0; fi
  askpass="$(mktemp)"
  trap 'rm -f "${askpass}"' EXIT
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- "exec op item get ${(q)DOTFILES_SSH_KEY_OP_ITEM} ${(q)vault_flag[@]} --fields password --reveal"
  } > "${askpass}"
  chmod 700 "${askpass}"
  DISPLAY=1 SSH_ASKPASS="${askpass}" SSH_ASKPASS_REQUIRE=force ssh-add "${key_path}" </dev/null
  log::info "ssh key loaded | path='${key_path}'"
}

# Create origin/main once (a bare clone has no remote-tracking refs). Runs after the ssh key:
# origin may be an ssh URL. Offline or keyless is a warning, not a failure; pull fills it in.
init_fetch() {
  repo_present shared || return 0
  if repo_git shared rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then log::info "origin/main known | git_dir='${TIER_GIT_DIR[shared]}'"; return 0; fi
  run_mut repo_git shared fetch -q origin && return 0
  log::warn "could not fetch origin; ahead/behind unknown until 'dotfiles pull' | url='$(repo_git shared config remote.origin.url 2>/dev/null || true)'"
}

#######################################
# Run the local tier's init hooks: every executable in LOCAL_INIT_HOOKS_DIR. A hook installs
# whatever its tier needs outside the tier's worktree — a LaunchAgent plist under ~/Library,
# a compiled helper under ~/.local/state — so a fresh machine gets it from `dotfiles init` and
# not from memory. Contract: idempotent, --dry-run means plan only, independent of the other
# hooks (so their order is irrelevant). Every hook runs even after one fails; the step fails
# if any did.
#######################################
init_local_hooks() {
  local -a hooks=("${LOCAL_INIT_HOOKS_DIR}"/*(N-.x:t))
  if (( ${#hooks} == 0 )); then log::info "no local init hooks | dir='${LOCAL_INIT_HOOKS_DIR}'"; return 0; fi
  local hook hrc rc=0
  local -a flags=()
  [[ "${DRY_RUN}" == true ]] && flags=(--dry-run)
  for hook in "${hooks[@]}"; do
    hrc=0
    "${LOCAL_INIT_HOOKS_DIR}/${hook}" "${flags[@]}" || hrc=$?
    if (( hrc == 0 )); then
      log::info "local init hook ok | hook='${hook}'"
    else
      log::err "local init hook failed | hook='${hook}' rc='${hrc}'"; rc=1
    fi
  done
  return "${rc}"
}

cmd_init() {
  local start="${EPOCHREALTIME}"
  check_prerequisites git || return 1
  step migrate init_migrate || return 1
  step clone init_clone || return 1
  step tracking init_tracking || return 1
  step checkout init_checkout || return 1
  step "hooks df" init_hooks shared || return 1
  if repo_present local; then
    step "hooks ldf" init_hooks local || return 1
  else
    log::info "no local tier on this machine | hint='new-machine apply local_dotfiles_repo'"
  fi
  step submodules init_submodules || return 1
  step skills init_skills || return 1
  step "ssh key" init_ssh_key || return 1
  step fetch init_fetch || return 1
  step "local hooks" init_local_hooks || return 1
  log::info "init done | took='$(elapsed "${start}")s' next='per-submodule setup (chrome-exoskeleton: exo deps ci && exo build) or new-machine setup'"
  step status cmd_status
}

cmd_pull() {
  local start="${EPOCHREALTIME}"
  check_prerequisites git || return 1
  slow=5 step pull run_mut repo_git shared pull --ff-only || return 1   # a fetch takes seconds; that is not slow
  cmd_init || return 1
  log::info "pull done | took='$(elapsed "${start}")s'"
}
