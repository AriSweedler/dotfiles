#!/usr/bin/env zsh
# Shared Google Drive helpers for the ari-hemingway skills. Source it; do not execute.
# Requires the logging lib to be sourced first (log::err, log::info).
#
#   source "${SKILLS_DIR}/ari-hemingway--lib/lib/drive.zsh"
#
# Provides: drive::folder_id_from, drive::gws_call, drive::resolve_folder.

if [[ -n "${_ARI_DRIVE_LIB_LOADED:-}" ]]; then
  return 0
fi
typeset -g _ARI_DRIVE_LIB_LOADED=1

readonly DRIVE_FOLDER_MIME="application/vnd.google-apps.folder"
readonly DRIVE_FOLDER_FIELDS="id,name,mimeType,driveId,capabilities/canAddChildren"
readonly DRIVE_GWS_TIMEOUT_SECS=30

source "${SKILLS_DIR:-${HOME}/.claude/skills}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

#######################################
# Reduce a Drive folder URL (https://drive.google.com/drive/[u/0/]folders/<id>[?...]) or a
# bare id to the id.
# Arguments: $1 - folder id or URL
# Outputs: the id on stdout
#######################################
drive::folder_id_from() {
  local folder="${1}"
  if [[ "${folder}" == *"/folders/"* ]]; then
    folder="${folder#*/folders/}"
    folder="${folder%%\?*}"
    folder="${folder%%/*}"
  fi
  echo "${folder}"
}

#######################################
# Run one gws call under a wall-clock cap; stdout lands in the reply file, stderr beside it.
# Globals: DRIVE_GWS_TIMEOUT_SECS
# Arguments: $1 - reply path, $@ - gws arguments
# Returns: the gws exit code, or 124 on timeout
#######################################
drive::gws_call() {
  local reply_file="${1}"; shift
  local exit_code=0
  run_with_timeout "${DRIVE_GWS_TIMEOUT_SECS}" "${reply_file}.err" gws "${@}" > "${reply_file}" || exit_code=$?
  if (( exit_code != 0 )); then
    log::err "gws call failed | args='${*}' exit_code='${exit_code}' error='$(tail -n 1 "${reply_file}.err" 2>/dev/null || true)'"
  fi
  return "${exit_code}"
}

#######################################
# Verify a Drive folder exists, is a folder, and accepts new files. supportsAllDrives covers
# shared-drive folders, which otherwise answer 404.
# Globals: DRIVE_FOLDER_MIME, DRIVE_FOLDER_FIELDS
# Arguments: $1 - folder id, $2 - reply path (the Drive reply JSON is left there for the caller)
# Outputs: the folder name on stdout
# Returns: 1 when the folder is missing, not a folder, or read-only
#######################################
drive::resolve_folder() {
  local folder="${1}" reply_file="${2}"
  local params mime name can_add
  params="$(jq -cn --arg id "${folder}" --arg f "${DRIVE_FOLDER_FIELDS}" '{fileId: $id, fields: $f, supportsAllDrives: true}')"
  if ! drive::gws_call "${reply_file}" drive files get --params "${params}"; then
    log::err "Folder not found or not readable | folder='${folder}' expected='a Drive folder id or drive.google.com/drive/folders URL the caller can open'"
    return 1
  fi
  mime="$(jq -r '.mimeType // ""' "${reply_file}")"
  name="$(jq -r '.name // ""' "${reply_file}")"
  can_add="$(jq -r '.capabilities.canAddChildren // false' "${reply_file}")"
  if [[ "${mime}" != "${DRIVE_FOLDER_MIME}" ]]; then
    log::err "Target is not a folder | folder='${folder}' mime_type='${mime}' expected='${DRIVE_FOLDER_MIME}'"
    return 1
  fi
  if [[ "${can_add}" != "true" ]]; then
    log::err "Cannot add files to folder | folder='${folder}' name='${name}' can_add_children='${can_add}' expected='true'"
    return 1
  fi
  echo "${name}"
}
