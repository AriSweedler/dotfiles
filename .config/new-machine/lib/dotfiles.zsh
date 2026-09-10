# lib/dotfiles.zsh — dotfiles::commit, the one place the two dotfiles tiers' git rules live.
# Sourced by bin/new-machine after lib/common.zsh; defines functions only.
#
#   global  ~/dotfiles.git             work tree $HOME         committed, never pushed (Ari runs git_df_push)
#   local   ~/.local/local-dotfiles.git work tree $HOME/.local  committed and pushed
#
# Explicit --git-dir/--work-tree throughout: the `git df`/`git ldf` aliases sit behind a config
# include a half-bootstrapped machine may lack, and the fake-HOME tests have no aliases at all.
#
# Requires lib/common.zsh (sourced first) for NEW_MACHINE_DF_GIT_DIR, NEW_MACHINE_LDF_GIT_DIR,
# log::* and nm::is_dry_run. Reads HOME and NM_NO_PUSH.

dotfiles::is_no_push() {
  case "${NM_NO_PUSH:-0}" in 0|false|no|"") return 1 ;; esac
  return 0
}

dotfiles::is_tier() {
  [[ "${1}" == global || "${1}" == local ]]
}

dotfiles::git_dir() {
  case "${1}" in
    global) print -r -- "${NEW_MACHINE_DF_GIT_DIR}" ;;
    local)  print -r -- "${NEW_MACHINE_LDF_GIT_DIR}" ;;
    *) print -u2 "dotfiles::git_dir: bad tier '${1}'"; return 64 ;;
  esac
}

dotfiles::work_tree() {
  case "${1}" in
    global) print -r -- "${HOME}" ;;
    local)  print -r -- "${HOME}/.local" ;;
    *) print -u2 "dotfiles::work_tree: bad tier '${1}'"; return 64 ;;
  esac
}

# git for one tier, e.g. `dotfiles::git local status --porcelain`.
dotfiles::git() {
  local tier="${1}"; shift
  dotfiles::is_tier "${tier}" || { print -u2 "dotfiles::git: bad tier '${tier}'"; return 64; }
  local git_dir work_tree
  git_dir="$(dotfiles::git_dir "${tier}")"
  work_tree="$(dotfiles::work_tree "${tier}")"
  git --git-dir="${git_dir}" --work-tree="${work_tree}" "$@"
}

# dotfiles::index_clean <global|local>: 0 when the tier can take a commit of exactly the paths
# a caller is about to add. Callers that edit files before committing run this first so a
# refusal leaves the work tree untouched. Returns 1 (logged) when the bare repo is missing or
# the index already holds unrelated changes.
dotfiles::index_clean() {
  local tier="${1}"
  dotfiles::is_tier "${tier}" || { print -u2 "dotfiles::index_clean: bad tier '${tier}'"; return 64; }
  local git_dir work_tree
  git_dir="$(dotfiles::git_dir "${tier}")"
  work_tree="$(dotfiles::work_tree "${tier}")"
  if [[ ! -d "${git_dir}" ]]; then
    log::err "bare repo missing | tier='${tier}' git_dir='${git_dir}' fix='new-machine apply dotfiles_repo|local_dotfiles_repo'"
    return 1
  fi
  local -a git=(git --git-dir="${git_dir}" --work-tree="${work_tree}")
  if ! "${git[@]}" diff --cached --quiet; then
    log::err "unrelated staged changes; commit or unstage first | tier='${tier}' git_dir='${git_dir}'"
    log::ERR "$("${git[@]}" diff --cached --name-only)"
    return 1
  fi
  return 0
}

# dotfiles::commit <global|local> <message> <abs path>...
#
# Refuses when the index already holds unrelated changes, so the commit contains exactly the
# given paths. Hooks run normally; a rejection leaves the files edited but uncommitted and is
# reported verbatim. Local pushes unless NM_NO_PUSH; a failed push is a warning, not an error,
# because the weekly `local_dotfiles_repo` check surfaces unpushed commits later.
# Returns 0 committed, 1 refused or rejected, 64 usage.
dotfiles::commit() {
  local tier="${1:-}" message="${2:-}"
  shift 2 2>/dev/null || { print -u2 "usage: dotfiles::commit <global|local> <message> <abs path>..."; return 64; }
  local -a paths=("$@")
  if ! dotfiles::is_tier "${tier}" || [[ -z "${message}" ]] || (( ${#paths} == 0 )); then
    print -u2 "usage: dotfiles::commit <global|local> <message> <abs path>..."
    return 64
  fi
  # Not `path`: that is zsh's array tied to PATH, and a local one empties it.
  local given
  for given in "${paths[@]}"; do
    if [[ "${given}" != /* ]]; then
      log::err "dotfiles::commit needs absolute paths | path='${given}'"
      return 64
    fi
  done

  local git_dir work_tree
  git_dir="$(dotfiles::git_dir "${tier}")"
  work_tree="$(dotfiles::work_tree "${tier}")"
  local -a git=(git --git-dir="${git_dir}" --work-tree="${work_tree}")
  local git_text="git --git-dir=${git_dir} --work-tree=${work_tree}"

  if nm::is_dry_run; then
    print -r -- "would run: ${git_text} add -- ${(j: :)paths}"
    print -r -- "would run: ${git_text} commit -m '${message%%$'\n'*}'"
    if [[ "${tier}" == local ]] && ! dotfiles::is_no_push; then
      print -r -- "would run: ${git_text} push"
    fi
    return 0
  fi

  dotfiles::index_clean "${tier}" || return 1

  local out rc=0
  out="$("${git[@]}" add -- "${paths[@]}" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    log::err "git add failed | tier='${tier}' rc='${rc}'"
    log::ERR "${out}"
    return 1
  fi
  rc=0
  out="$("${git[@]}" commit -m "${message}" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    log::err "commit rejected; files are edited but uncommitted | tier='${tier}' rc='${rc}'"
    log::ERR "${out}"
    return 1
  fi

  print -r -- "[${tier}] $("${git[@]}" log --oneline -1)"
  case "${tier}" in
    global)
      print -r -- 'Run `git_df_push` when ready.'
      ;;
    local)
      if dotfiles::is_no_push; then
        log::info "push skipped | tier='local' fix='git ldf push'"
        return 0
      fi
      rc=0
      out="$("${git[@]}" push 2>&1)" || rc=$?
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
