#!/usr/bin/env zsh
# The proposal's blobs: where a skill is versioned, what its working tree holds
# against HEAD as one line per changed file, and which other drivers of the same
# skill are live. Source it after logging.zsh and the registry lib; do not execute.
#
# An entry line is `<mode> <blob> <path>` for a file the proposal adds or
# changes, or `deleted - <path>` for one it removes; <path> is relative to the
# skill directory. record_blobs.zsh writes them into the Commit command and
# commit_blobs.zsh refuses unless the working tree still yields the same lines.

[[ -n "${_ARI_SKILL_UPDATE_BLOBS_ZSH:-}" ]] && return 0
readonly _ARI_SKILL_UPDATE_BLOBS_ZSH=1

zmodload -F zsh/stat b:zstat
zmodload -F zsh/datetime p:EPOCHSECONDS

readonly INVESTIGATION_ROOT="${SKILL_UPDATE_ROOT:-/tmp/skill-update}"
# A sibling driver's folder counts as live when a file in it is newer than both
# the skill's last commit and this window.
readonly LIVE_WINDOW_SECONDS=$(( 24 * 3600 ))

#######################################
# Run git in the repo that versions the skill: a submodule's own repo, else the
# tier's bare repo through its df/ldf alias, from the worktree root so that
# paths are worktree-relative.
# Globals: TIER_WORKTREES
# Arguments:
#   $1 - tier (df|ldf)
#   $2 - source (empty, or submodule:<path relative to the tier worktree>)
#   $@ - git arguments
#######################################
repo_git() {
  local tier="${1}" source="${2}"
  shift 2
  if [[ "${source}" == submodule:* ]]; then
    git -C "${TIER_WORKTREES[${tier}]}/${source#submodule:}" "${@}"
    return
  fi
  git -C "${TIER_WORKTREES[${tier}]}" "${tier}" "${@}"
}

#######################################
# Print the worktree root repo_git runs from.
# Globals: TIER_WORKTREES
# Arguments:
#   $1 - tier
#   $2 - source
#######################################
repo_root() {
  local tier="${1}" source="${2}"
  if [[ "${source}" == submodule:* ]]; then
    print -r -- "${TIER_WORKTREES[${tier}]}/${source#submodule:}"
    return
  fi
  print -r -- "${TIER_WORKTREES[${tier}]}"
}

#######################################
# Print the skill directory's path relative to repo_root.
# Globals: TIER_ROOTS, TIER_WORKTREES
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill name
#######################################
repo_skill_rel() {
  local tier="${1}" source="${2}" skill="${3}"
  if [[ "${source}" == submodule:* ]]; then
    print -r -- "skills/${skill}"
    return
  fi
  print -r -- "${TIER_ROOTS[${tier}]#${TIER_WORKTREES[${tier}]}/}/${skill}"
}

#######################################
# Refuse when the repo that versions the skill has no commit yet: every diff and
# stage here is against HEAD.
# Arguments:
#   $1 - tier
#   $2 - source
# Returns: 1 when HEAD is unborn
#######################################
require_head() {
  local tier="${1}" source="${2}"
  repo_git "${tier}" "${source}" rev-parse --verify -q HEAD >/dev/null 2>&1 && return 0
  log::err "The repo has no commits yet | repo='$(repo_root "${tier}" "${source}")' hint='make its first commit per /ari-dotfile--submodule, then re-run'"
  return 1
}

#######################################
# Print `<mode> <blob>` for one file as git would store it, writing the blob to
# the object store when asked.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - absolute file path
#   $4 - repo-relative path (for attributes)
#   $5 - write (true|false)
#######################################
file_mode_blob() {
  local tier="${1}" source="${2}" file="${3}" rel="${4}" write="${5}"
  local -a write_flag=()
  [[ "${write}" == "true" ]] && write_flag=(-w)
  if [[ -L "${file}" ]]; then
    print -r -- "120000 $(print -rn -- "$(readlink "${file}")" | repo_git "${tier}" "${source}" hash-object "${write_flag[@]}" --stdin)"
    return
  fi
  local mode=100644
  [[ -x "${file}" ]] && mode=100755
  print -r -- "${mode} $(repo_git "${tier}" "${source}" hash-object "${write_flag[@]}" --path="${rel}" --stdin < "${file}")"
}

#######################################
# Print the entry lines for every file under the skill directory whose working
# tree differs from HEAD, sorted by path (sort -k3). Candidates are HEAD's files, the
# index's, and untracked files the repo does not ignore.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - write (true|false)
#######################################
changed_entries() {
  local tier="${1}" source="${2}" skill_rel="${3}" write="${4}"
  local root
  root="$(repo_root "${tier}" "${source}")"
  local -a candidates
  candidates=("${(@fu)$(
    repo_git "${tier}" "${source}" ls-tree -r --name-only HEAD -- "${skill_rel}" 2>/dev/null || true
    repo_git "${tier}" "${source}" ls-files --cached --others --exclude-standard -- "${skill_rel}"
  )}")
  candidates=("${(@o)candidates:#}")
  local rel head_entry now
  for rel in "${candidates[@]}"; do
    head_entry="$(repo_git "${tier}" "${source}" ls-tree HEAD -- "${rel}" 2>/dev/null | awk '{ print $1, $3 }' || true)"
    if [[ ! -e "${root}/${rel}" && ! -L "${root}/${rel}" ]]; then
      [[ -n "${head_entry}" ]] && print -r -- "deleted - ${rel#${skill_rel}/}"
      continue
    fi
    now="$(file_mode_blob "${tier}" "${source}" "${root}/${rel}" "${rel}" "${write}")"
    [[ "${now}" == "${head_entry}" ]] || print -r -- "${now} ${rel#${skill_rel}/}"
  done | sort -k3
}

#######################################
# Print the entry lines for every file of a skill directory not yet in any tier
# (an adoption): all of them are added. Skips what init.zsh skips and what the
# destination repo would ignore.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - the skill's real directory
#   $4 - its destination, repo-relative
#   $5 - write (true|false)
#######################################
adopt_entries() {
  local tier="${1}" source="${2}" dir="${3}" dest_rel="${4}" write="${5}"
  local -a files
  files=("${(@f)$(find "${dir}/" \( -name .git -o -name __pycache__ -o -name node_modules -o -name .DS_Store \) -prune -o \( -type f -o -type l \) -print | sort)}")
  files=("${(@)files:#}")
  local file rel ignored
  ignored="$(printf '%s\n' "${files[@]#${dir}/}" | awk -v p="${dest_rel}/" 'NF { print p $0 }' | repo_git "${tier}" "${source}" check-ignore --no-index --stdin || true)"
  for file in "${files[@]}"; do
    rel="${file#${dir}/}"
    [[ $'\n'"${ignored}"$'\n' == *$'\n'"${dest_rel}/${rel}"$'\n'* ]] && continue
    print -r -- "$(file_mode_blob "${tier}" "${source}" "${file}" "${dest_rel}/${rel}" "${write}") ${rel}"
  done | sort -k3
}

#######################################
# Print the tree id HEAD holds at the skill directory, or `none`.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#######################################
base_tree() {
  local tier="${1}" source="${2}" skill_rel="${3}"
  local tree
  tree="$(repo_git "${tier}" "${source}" rev-parse --verify -q "HEAD:${skill_rel}" 2>/dev/null || true)"
  print -r -- "${tree:-none}"
}

#######################################
# Print the epoch of the last commit touching the skill directory, or 0.
# Arguments:
#   $1 - tier (empty when no tier holds the skill)
#   $2 - source
#   $3 - skill directory, repo-relative
#######################################
last_commit_epoch() {
  local tier="${1}" source="${2}" skill_rel="${3}"
  [[ -n "${tier}" && "${tier}" != "-" ]] || { print 0; return; }
  local epoch
  epoch="$(repo_git "${tier}" "${source}" log -1 --format=%ct -- "${skill_rel}" 2>/dev/null || true)"
  print -r -- "${epoch:-0}"
}

#######################################
# Print, comma-separated, every other investigation folder of the skill holding
# a file newer than its last commit and LIVE_WINDOW_SECONDS: another driver that
# may be editing the same files.
# Globals: INVESTIGATION_ROOT, LIVE_WINDOW_SECONDS
# Arguments:
#   $1 - skill name
#   $2 - this driver's investigation folder
#   $3 - epoch of the skill's last commit (0 if none)
#######################################
live_sibling_dirs() {
  local skill="${1}" own="${2}" committed="${3}"
  local since=$(( EPOCHSECONDS - LIVE_WINDOW_SECONDS ))
  (( committed > since )) && since="${committed}"
  local dir mtime
  local -a newest
  local -a live=()
  for dir in "${INVESTIGATION_ROOT}/${skill}"/*(N/); do
    # :A on both: /tmp is a symlink on macOS, and the caller's form may differ.
    [[ "${dir:A}" == "${own:A}" ]] && continue
    newest=("${dir}"/**/*(N.om[1]))
    (( ${#newest} > 0 )) || continue
    mtime="$(zstat +mtime -- "${newest[1]}")"
    (( mtime > since )) && live+=("${dir}")
  done
  print -r -- "${(j:,:)live}"
}

#######################################
# Print, comma-separated, the paths on which two sets of entry lines disagree.
# Arguments:
#   $1 - expected entry lines
#   $2 - actual entry lines
#######################################
mismatched_paths() {
  local expected="${1}" actual="${2}"
  { diff <(print -r -- "${expected}") <(print -r -- "${actual}") || true; } \
    | awk '/^[<>] / { sub(/^[<>] [^ ]+ [^ ]+ /, ""); print }' | sort -u | paste -sd, -
}

# --- Shared files outside a skill directory ---
# A proposal may also carry files under a tier's shared roots (the tier's
# `<skills root>/../lib`, ~/.config/claude/lib for df). Their entry lines name
# the path as `@shared:<path relative to the repo root>` and are guarded like a
# skill file: the working tree must still yield the blob, and HEAD must still
# hold the blob the proposal was diffed against.

readonly SHARED_ENTRY_PREFIX="@shared:"

#######################################
# Print the tier's allowed shared roots, repo-relative, one per line. Only a tier
# whose skills root is named `skills` has a sibling `lib`; the local tier has no
# shared directory, so it allows none.
# Globals: TIER_ROOTS, TIER_WORKTREES
# Arguments:
#   $1 - tier
#######################################
shared_roots() {
  local tier="${1}" root="${TIER_ROOTS[${1}]}"
  [[ "${root:t}" == skills ]] || return 0
  local lib="${root:h}/lib"
  print -r -- "${lib#${TIER_WORKTREES[${tier}]}/}"
}

#######################################
# True (0) when a repo-relative path names something under an allowed shared root.
# Arguments:
#   $1 - tier
#   $2 - repo-relative path
#######################################
is_shared_path() {
  local tier="${1}" rel="${2}" root
  [[ -n "${rel}" && "${rel}" != (/*|*..*) ]] || return 1
  for root in "${(@f)$(shared_roots "${tier}")}"; do
    [[ -n "${root}" && "${rel}" == "${root}/"?* ]] && return 0
  done
  return 1
}

#######################################
# Print the entry lines for each named shared path whose working tree differs
# from HEAD; the path of a line is `@shared:<path>`.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - write (true|false)
#   $@ - repo-relative shared paths
#######################################
shared_entries() {
  local tier="${1}" source="${2}" write="${3}"
  shift 3
  local root rel head_entry now
  root="$(repo_root "${tier}" "${source}")"
  for rel in "$@"; do
    head_entry="$(repo_git "${tier}" "${source}" ls-tree HEAD -- "${rel}" 2>/dev/null | awk '{ print $1, $3 }' || true)"
    if [[ ! -e "${root}/${rel}" && ! -L "${root}/${rel}" ]]; then
      [[ -n "${head_entry}" ]] && print -r -- "deleted - ${SHARED_ENTRY_PREFIX}${rel}"
      continue
    fi
    now="$(file_mode_blob "${tier}" "${source}" "${root}/${rel}" "${rel}" "${write}")"
    [[ "${now}" == "${head_entry}" ]] || print -r -- "${now} ${SHARED_ENTRY_PREFIX}${rel}"
  done
}

#######################################
# Print the blob HEAD holds at a repo-relative path, or `none`.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - repo-relative path
#######################################
head_blob() {
  local blob
  blob="$(repo_git "${1}" "${2}" rev-parse --verify -q "HEAD:${3}" 2>/dev/null || true)"
  print -r -- "${blob:-none}"
}

#######################################
# Print the repo-relative path an entry's path names: a shared path as it is,
# anything else under the skill directory.
# Arguments:
#   $1 - skill directory, repo-relative
#   $2 - the entry's path
#######################################
entry_repo_path() {
  local skill_rel="${1}" file="${2}"
  if [[ "${file}" == "${SHARED_ENTRY_PREFIX}"* ]]; then
    print -r -- "${file#${SHARED_ENTRY_PREFIX}}"
    return
  fi
  print -r -- "${skill_rel}/${file}"
}

#######################################
# Print the repo-relative shared paths the entry lines on stdin name.
# Arguments: None
#######################################
shared_paths_of() {
  awk -v p="${SHARED_ENTRY_PREFIX}" 'NF { sub(/^[^ ]+ [^ ]+ /, ""); if (index($0, p) == 1) print substr($0, length(p) + 1) }'
}

#######################################
# Print two blocks of entry lines as one block, sorted by path (sort -k3).
# Arguments:
#   $1 - entry lines
#   $2 - more entry lines
#######################################
merge_entries() {
  print -r -- "${1}"$'\n'"${2}" | awk 'NF' | sort -k3
}
