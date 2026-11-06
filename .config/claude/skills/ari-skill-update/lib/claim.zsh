#!/usr/bin/env zsh
# One driver per skill, across sessions: the claim. It is a symlink
# <investigation root>/<skill>/.claim whose target is the owning driver's
# investigation folder, so taking it is one atomic `ln -s` and the owner is
# `readlink`. init.zsh takes it, record_blobs.zsh and commit_blobs.zsh check it,
# commit_blobs.zsh releases it. A claim is stale when its owner's folder is gone
# or nothing in it, nor the claim itself, changed within CLAIM_STALE_SECONDS.
# Source it after logging.zsh and blobs.zsh; do not execute.
#
# The claim lives in the investigation root, which holds only this tool's own
# bookkeeping, so taking it is not a mutation in the dry-run sense (like
# mk_investigation_dir); record_blobs.zsh still takes it only under --execute.

[[ -n "${_ARI_SKILL_UPDATE_CLAIM_ZSH:-}" ]] && return 0
readonly _ARI_SKILL_UPDATE_CLAIM_ZSH=1

readonly CLAIM_STALE_SECONDS="${SKILL_UPDATE_CLAIM_STALE_SECONDS:-7200}"

#######################################
# Print the claim's path for a skill.
# Globals: INVESTIGATION_ROOT
# Arguments:
#   $1 - skill name
#######################################
claim_path() {
  print -r -- "${INVESTIGATION_ROOT}/${1}/.claim"
}

#######################################
# Print the owning investigation folder, or nothing when there is no claim.
# Arguments:
#   $1 - skill name
#######################################
claim_owner() {
  local link
  link="$(claim_path "${1}")"
  [[ -L "${link}" ]] || return 0
  readlink "${link}"
}

#######################################
# True (0) when the claim's owner has shown no sign of life for
# CLAIM_STALE_SECONDS: its folder is gone, or the claim and every file in the
# folder are older than that.
# Globals: CLAIM_STALE_SECONDS, EPOCHSECONDS
# Arguments:
#   $1 - skill name
#######################################
claim_is_stale() {
  local skill="${1}" link owner
  link="$(claim_path "${skill}")"
  owner="$(claim_owner "${skill}")"
  [[ -n "${owner}" ]] || return 0
  [[ -d "${owner}" ]] || return 0
  local newest mtime
  newest="$(zstat -L +mtime -- "${link}" 2>/dev/null)" || return 0
  local -a files
  files=("${owner}"/**/*(N.om[1]))
  if (( ${#files} > 0 )); then
    mtime="$(zstat +mtime -- "${files[1]}")"
    (( mtime > newest )) && newest="${mtime}"
  fi
  (( EPOCHSECONDS - newest > CLAIM_STALE_SECONDS ))
}

#######################################
# Print the live owner of the claim when it is not `me`, else nothing: the
# driver in the way. A stale or absent claim has none.
# Arguments:
#   $1 - skill name
#   $2 - my investigation folder
#######################################
claim_blocker() {
  local skill="${1}" me="${2}" owner
  owner="$(claim_owner "${skill}")"
  [[ -n "${owner}" ]] || return 0
  [[ -n "${me}" && "${owner:A}" == "${me:A}" ]] && return 0
  claim_is_stale "${skill}" && return 0
  print -r -- "${owner}"
}

#######################################
# Take the claim for my investigation folder. Prints how: taken, renewed (it
# was already mine), taken-stale, or taken-over (a live owner, --takeover).
# Returns 1, printing `held <owner>`, when another live driver holds it.
# Arguments:
#   $1 - skill name
#   $2 - my investigation folder
#   $3 - takeover (true|false)
#######################################
claim_take() {
  local skill="${1}" me="${2:A}" takeover="${3}"
  local link owner how=taken
  link="$(claim_path "${skill}")"
  mkdir -p -- "${link:h}"
  if [[ -e "${link}" && ! -L "${link}" ]]; then
    print -r -- "held not-a-symlink:${link}"
    return 1
  fi
  if ln -sn -- "${me}" "${link}" 2>/dev/null; then
    print -r -- taken
    return 0
  fi
  owner="$(claim_owner "${skill}")"
  if [[ -n "${owner}" && "${owner:A}" == "${me:A}" ]]; then
    touch -h -- "${link}"
    print -r -- renewed
    return 0
  fi
  if [[ -n "${owner}" ]] && claim_is_stale "${skill}"; then
    how=taken-stale
  elif [[ -n "${owner}" && "${takeover}" == "true" ]]; then
    how=taken-over
  elif [[ -n "${owner}" ]]; then
    print -r -- "held ${owner}"
    return 1
  fi
  local moved="${link}.gone.$$" moved_owner=""
  mv -- "${link}" "${moved}" 2>/dev/null || true
  [[ -L "${moved}" ]] && moved_owner="$(readlink "${moved}")"
  if [[ -n "${moved_owner}" && "${moved_owner}" != "${owner}" ]]; then
    # Another driver took the claim between the check and the mv: give it back.
    ln -sn -- "${moved_owner}" "${link}" 2>/dev/null || true
    rm -f -- "${moved}"
    print -r -- "held ${moved_owner}"
    return 1
  fi
  rm -f -- "${moved}"
  if ln -sn -- "${me}" "${link}" 2>/dev/null; then
    print -r -- "${how}"
    return 0
  fi
  print -r -- "held $(claim_owner "${skill}")"
  return 1
}

#######################################
# Release the claim when it is mine; another driver's claim stays.
# Arguments:
#   $1 - skill name
#   $2 - my investigation folder
#######################################
claim_release() {
  local skill="${1}" me="${2}" owner
  owner="$(claim_owner "${skill}")"
  [[ -n "${owner}" && "${owner:A}" == "${me:A}" ]] || return 0
  rm -f -- "$(claim_path "${skill}")"
}
