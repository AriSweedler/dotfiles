#!/usr/bin/env zsh
# Pick the Drive folder a scaffold's Docs are published into: the given parent when it is
# empty, otherwise a child folder named after the topic (reused when it already exists,
# created otherwise). Creating that child is the only mutation; --dry-run validates it
# with Drive without creating anything.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Constants ---

readonly FOLDER_MIME="application/vnd.google-apps.folder"
readonly FOLDER_FIELDS="id,name,mimeType,driveId,capabilities/canAddChildren"
readonly GWS_TIMEOUT_SECS=30
readonly LIST_PAGE_SIZE=200

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in gws jq; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Drive helpers ---

#######################################
# Reduce a Drive folder URL (https://drive.google.com/drive/[u/0/]folders/<id>[?...]) or a
# bare id to the id.
# Arguments: $1 - folder id or URL
# Outputs: the id on stdout
#######################################
folder_id_from() {
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
# Globals: GWS_TIMEOUT_SECS
# Arguments: $1 - reply path, $@ - gws arguments
# Returns: the gws exit code, or 124 on timeout
#######################################
gws_call() {
  local reply_file="${1}"; shift
  local exit_code=0
  run_with_timeout "${GWS_TIMEOUT_SECS}" "${reply_file}.err" gws "${@}" > "${reply_file}" || exit_code=$?
  if (( exit_code != 0 )); then
    log::err "gws call failed | args='${*}' exit_code='${exit_code}' error='$(tail -n 1 "${reply_file}.err" 2>/dev/null || true)'"
  fi
  return "${exit_code}"
}

#######################################
# Verify the parent exists, is a folder, and accepts new files. supportsAllDrives covers
# shared-drive folders, which otherwise answer 404.
# Globals: FOLDER_MIME, FOLDER_FIELDS
# Arguments: $1 - parent id, $2 - reply path
# Outputs: the parent's name on stdout
#######################################
resolve_parent() {
  local parent="${1}" reply_file="${2}"
  local params mime name can_add
  params="$(jq -cn --arg id "${parent}" --arg f "${FOLDER_FIELDS}" '{fileId: $id, fields: $f, supportsAllDrives: true}')"
  gws_call "${reply_file}" drive files get --params "${params}" || return 1
  mime="$(jq -r '.mimeType // ""' "${reply_file}")"
  name="$(jq -r '.name // ""' "${reply_file}")"
  can_add="$(jq -r '.capabilities.canAddChildren // false' "${reply_file}")"
  if [[ "${mime}" != "${FOLDER_MIME}" ]]; then
    log::err "Parent is not a folder | parent='${parent}' mime_type='${mime}' expected='${FOLDER_MIME}'"
    return 1
  fi
  if [[ "${can_add}" != "true" ]]; then
    log::err "Cannot add files to parent | parent='${parent}' name='${name}' can_add_children='${can_add}' expected='true'"
    return 1
  fi
  echo "${name}"
}

#######################################
# List the parent's non-trashed children into the reply file.
# Globals: LIST_PAGE_SIZE
# Arguments: $1 - parent id, $2 - reply path
#######################################
list_children() {
  local parent="${1}" reply_file="${2}"
  local params
  params="$(jq -cn --arg q "'${parent}' in parents and trashed = false" --argjson n "${LIST_PAGE_SIZE}" \
    '{q: $q, pageSize: $n, fields: "files(id,name,mimeType)", supportsAllDrives: true, includeItemsFromAllDrives: true}')"
  gws_call "${reply_file}" drive files list --params "${params}"
}

#######################################
# Create the child folder under the parent. Under dry-run, Drive validates the request and
# nothing is created.
# Globals: FOLDER_MIME
# Arguments: $1 - parent id, $2 - child name, $3 - dry_run, $4 - reply path
# Outputs: the new folder's id on stdout (empty under dry-run)
#######################################
create_child() {
  local parent="${1}" name="${2}" dry_run="${3}" reply_file="${4}"
  local meta params
  local -a flags
  meta="$(jq -cn --arg name "${name}" --arg mime "${FOLDER_MIME}" --arg parent "${parent}" '{name: $name, mimeType: $mime, parents: [$parent]}')"
  params="$(jq -cn '{fields: "id,name", supportsAllDrives: true}')"
  [[ "${dry_run}" == "true" ]] && flags+=(--dry-run)
  gws_call "${reply_file}" drive files create "${flags[@]}" --json "${meta}" --params "${params}" || return 1
  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run: Drive accepted the create request; nothing created | parent='${parent}' name='${name}'"
    return 0
  fi
  jq -r '.id // empty' "${reply_file}"
}

#######################################
# Decide where the Docs go. Empty parent: the parent itself. Existing child with the topic
# name: that child. Otherwise: a new child (validated only under dry-run).
# Arguments: $1 - parent id, $2 - child name, $3 - dry_run, $4 - children reply path, $5 - work dir
# Outputs: one line "folder_id<TAB>created<TAB>reason" on stdout
#######################################
choose_target() {
  local parent="${1}" name="${2}" dry_run="${3}" children_file="${4}" work="${5}"
  local children_count existing folder_id
  children_count="$(jq '.files | length' "${children_file}")"
  if (( children_count == 0 )); then
    log::info "Parent is empty; publishing into it | parent='${parent}'"
    printf '%s\t%s\t%s\n' "${parent}" "false" "parent_empty"
    return 0
  fi
  existing="$(jq -r --arg n "${name}" --arg mime "${FOLDER_MIME}" '[.files[] | select(.mimeType == $mime and .name == $n)][0].id // empty' "${children_file}")"
  if [[ -n "${existing}" ]]; then
    log::info "Reusing existing child folder | parent='${parent}' name='${name}' folder_id='${existing}'"
    printf '%s\t%s\t%s\n' "${existing}" "false" "child_exists"
    return 0
  fi
  log::info "Parent has children; creating a child folder | parent='${parent}' children='${children_count}' name='${name}' dry_run='${dry_run}'"
  folder_id="$(create_child "${parent}" "${name}" "${dry_run}" "${work}/create.json")" || return 1
  if [[ "${dry_run}" == "true" ]]; then
    printf '%s\t%s\t%s\n' "" "would_create" "child_missing"
    return 0
  fi
  printf '%s\t%s\t%s\n' "${folder_id}" "true" "child_missing"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}drive_subfolder${c_rst} — choose or create the Drive folder a scaffold's Docs are published into

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/drive_subfolder.zsh --parent ID_OR_URL --name NAME [--dry-run]

${c_bold}Options:${c_rst}
  --parent ID_OR_URL  The user's folder: a Drive id or drive.google.com/drive/folders URL (required)
  --name NAME         Child folder name, normally the topic (required)
  --dry-run           Validate with Drive; create nothing
  -h, --help          Show this help

${c_bold}Output:${c_rst} key=value lines. folder_id is the parent when it is empty, else the child named NAME
(reused if present, created otherwise; empty under --dry-run when it would be created).
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local parent="" name="" dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --parent)   parent="${2:?--parent requires a value}"; shift 2 ;;
    --name)     name="${2:?--name requires a value}"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  parent="$(folder_id_from "${parent}")"

  # === VALIDATE ===
  [[ -n "${parent}" ]] || { log::err "Missing --parent"; help; return 1; }
  [[ -n "${name}" ]] || { log::err "Missing --name"; help; return 1; }

  # === LOGIC ===
  local work parent_name folder_id created reason folder_name children_count
  work="$(mktemp -d)"
  parent_name="$(resolve_parent "${parent}" "${work}/parent.json")" || return 1
  list_children "${parent}" "${work}/children.json" || return 1
  children_count="$(jq '.files | length' "${work}/children.json")"
  IFS=$'\t' read -r folder_id created reason < <(choose_target "${parent}" "${name}" "${dry_run}" "${work}/children.json" "${work}")
  [[ -n "${reason}" ]] || { log::err "Could not choose a target folder | parent='${parent}' name='${name}'"; return 1; }
  folder_name="${name}"
  [[ "${reason}" == "parent_empty" ]] && folder_name="${parent_name}"
  log::ok "Target folder chosen | folder_id='${folder_id}' folder_name='${folder_name}' created='${created}' reason='${reason}'"

  cat <<EOF
parent_id=${parent}
parent_name=${parent_name}
parent_children=${children_count}
folder_id=${folder_id}
folder_name=${folder_name}
created=${created}
reason=${reason}
EOF
}

main "${@}"
