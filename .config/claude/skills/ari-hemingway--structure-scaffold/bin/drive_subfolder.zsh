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

readonly LIST_PAGE_SIZE=200

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-hemingway--lib/lib/drive.zsh"

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

# --- Drive helpers (shared ones come from ari-hemingway--lib/lib/drive.zsh) ---

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
  drive::gws_call "${reply_file}" drive files list --params "${params}"
}

#######################################
# Create the child folder under the parent. Under dry-run, Drive validates the request and
# nothing is created.
# Globals: DRIVE_FOLDER_MIME
# Arguments: $1 - parent id, $2 - child name, $3 - dry_run, $4 - reply path
# Outputs: the new folder's id on stdout (empty under dry-run)
#######################################
create_child() {
  local parent="${1}" name="${2}" dry_run="${3}" reply_file="${4}"
  local meta params
  local -a flags
  meta="$(jq -cn --arg name "${name}" --arg mime "${DRIVE_FOLDER_MIME}" --arg parent "${parent}" '{name: $name, mimeType: $mime, parents: [$parent]}')"
  params="$(jq -cn '{fields: "id,name", supportsAllDrives: true}')"
  [[ "${dry_run}" == "true" ]] && flags+=(--dry-run)
  drive::gws_call "${reply_file}" drive files create "${flags[@]}" --json "${meta}" --params "${params}" || return 1
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
# Outputs: one line "folder_id|created|reason" on stdout ('|' keeps an empty folder_id in place)
#######################################
choose_target() {
  local parent="${1}" name="${2}" dry_run="${3}" children_file="${4}" work="${5}"
  local children_count existing folder_id
  children_count="$(jq '.files | length' "${children_file}")"
  if (( children_count == 0 )); then
    log::info "Parent is empty; publishing into it | parent='${parent}'"
    printf '%s|%s|%s\n' "${parent}" "false" "parent_empty"
    return 0
  fi
  existing="$(jq -r --arg n "${name}" --arg mime "${DRIVE_FOLDER_MIME}" '[.files[] | select(.mimeType == $mime and .name == $n)][0].id // empty' "${children_file}")"
  if [[ -n "${existing}" ]]; then
    log::info "Reusing existing child folder | parent='${parent}' name='${name}' folder_id='${existing}'"
    printf '%s|%s|%s\n' "${existing}" "false" "child_exists"
    return 0
  fi
  log::info "Parent has children; creating a child folder | parent='${parent}' children='${children_count}' name='${name}' dry_run='${dry_run}'"
  folder_id="$(create_child "${parent}" "${name}" "${dry_run}" "${work}/create.json")" || return 1
  if [[ "${dry_run}" == "true" ]]; then
    printf '%s|%s|%s\n' "" "would_create" "child_missing"
    return 0
  fi
  printf '%s|%s|%s\n' "${folder_id}" "true" "child_missing"
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
  parent="$(drive::folder_id_from "${parent}")"

  # === VALIDATE ===
  [[ -n "${parent}" ]] || { log::err "Missing --parent"; help; return 1; }
  [[ -n "${name}" ]] || { log::err "Missing --name"; help; return 1; }

  # === LOGIC ===
  local work parent_name folder_id created reason folder_name children_count
  work="$(mktemp -d)"
  parent_name="$(drive::resolve_folder "${parent}" "${work}/parent.json")" || return 1
  list_children "${parent}" "${work}/children.json" || return 1
  children_count="$(jq '.files | length' "${work}/children.json")"
  IFS='|' read -r folder_id created reason < <(choose_target "${parent}" "${name}" "${dry_run}" "${work}/children.json" "${work}")
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
