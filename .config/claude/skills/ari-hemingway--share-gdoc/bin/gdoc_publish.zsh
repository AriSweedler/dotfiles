#!/usr/bin/env zsh
# Publish a markdown draft as a Google Doc and finish it in the same run: create (inside a
# Drive folder with --folder, or in My Drive) or update in place with --doc via Drive's
# markdown→Docs conversion, then style table header rows and verify every image fits one
# page (gdoc_finish.zsh). Prints the URL. The draft's first line is the Doc title and is
# not uploaded as body; --title overrides.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Constants ---

readonly DOC_MIME="application/vnd.google-apps.document"
readonly FOLDER_MIME="application/vnd.google-apps.folder"
readonly REPLY_FIELDS="id,name,parents,webViewLink"
readonly FOLDER_FIELDS="id,name,mimeType,driveId,capabilities/canAddChildren"

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Prerequisites ---

#######################################
# Check that required binaries and the finishing script are present.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local cmd
  local missing=()
  for cmd in gws jq; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  [[ -f "${SCRIPT_DIR}/gdoc_finish.zsh" ]] || missing+=("${SCRIPT_DIR}/gdoc_finish.zsh")
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands or files | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# Reduce a Google Doc URL or bare id to the id.
# Arguments: $1 - id or URL
#######################################
doc_id_from() {
  local doc="${1}"
  if [[ "${doc}" == *"/d/"* ]]; then
    doc="${doc#*/d/}"
    doc="${doc%%/*}"
  fi
  echo "${doc}"
}

#######################################
# Reduce a Drive folder URL (https://drive.google.com/drive/[u/0/]folders/<id>[?...]) or bare id
# to the id.
# Arguments: $1 - id or URL
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

########################################################################
# Business logic
########################################################################

#######################################
# Stage the upload body. Without --title the first line is the title and is stripped.
# Arguments: $1 - draft path, $2 - title ("" = derive), $3 - body output path
# Outputs: the resolved title on stdout
#######################################
stage_body() {
  local file="${1}" title="${2}" body="${3}"
  if [[ -n "${title}" ]]; then
    log::info "Using explicit title; whole file is body | title='${title}'"
    cp "${file}" "${body}"
    echo "${title}"
    return
  fi
  title="$(head -n 1 "${file}")"
  log::info "Using first line as title; stripped from body | title='${title}'"
  tail -n +2 "${file}" | jq -Rs 'ltrimstr("\n")' -r > "${body}"
  echo "${title}"
}

#######################################
# Verify the Drive folder a new Doc will be created in: it must exist, be a folder, and accept
# new files. supportsAllDrives covers shared-drive folders, which otherwise answer 404.
# Globals: FOLDER_MIME, FOLDER_FIELDS
# Arguments: $1 - folder id, $2 - reply path
# Outputs: the folder name on stdout
#######################################
resolve_folder() {
  local folder="${1}" reply_file="${2}"
  local params
  params="$(jq -cn --arg id "${folder}" --arg f "${FOLDER_FIELDS}" '{fileId: $id, fields: $f, supportsAllDrives: true}')"
  if ! gws drive files get --params "${params}" > "${reply_file}" 2> "${reply_file}.err"; then
    log::err "Folder not found or not readable | folder='${folder}' error='$(tail -n 1 "${reply_file}.err")' expected='a Drive folder id or drive.google.com/drive/folders URL the caller can open'"
    return 1
  fi
  local mime can_add name
  mime="$(jq -r '.mimeType // empty' "${reply_file}")"
  can_add="$(jq -r '.capabilities.canAddChildren // false' "${reply_file}")"
  name="$(jq -r '.name // empty' "${reply_file}")"
  if [[ "${mime}" != "${FOLDER_MIME}" ]]; then
    log::err "Target is not a folder | folder='${folder}' mime_type='${mime}' expected='${FOLDER_MIME}'"
    return 1
  fi
  if [[ "${can_add}" != "true" ]]; then
    log::err "Cannot add files to folder | folder='${folder}' name='${name}' can_add_children='${can_add}' expected='true'"
    return 1
  fi
  echo "${name}"
}

#######################################
# Create a new Doc (inside folder when given) or update an existing one from body.md in the cwd.
# Arguments: $1 - title, $2 - doc id ("" = create), $3 - folder id ("" = My Drive), $4 - dry_run, $5 - reply path
# Outputs: "created" or "updated" on stdout
#######################################
upload_doc() {
  local title="${1}" doc="${2}" folder="${3}" dry_run="${4}" reply_file="${5}"
  local -a flags
  [[ "${dry_run}" == "true" ]] && flags+=(--dry-run)
  if [[ -z "${doc}" ]]; then
    local meta
    # parents places the Doc at creation; there is no later move.
    meta="$(jq -cn --arg name "${title}" --arg mime "${DOC_MIME}" --arg parent "${folder}" \
      '{name: $name, mimeType: $mime} + (if $parent == "" then {} else {parents: [$parent]} end)')"
    local params
    params="$(jq -cn --arg f "${REPLY_FIELDS}" '{fields: $f, supportsAllDrives: true}')"
    gws drive files create "${flags[@]}" --json "${meta}" --upload body.md --upload-content-type text/markdown --params "${params}" > "${reply_file}"
    echo "created"
    return
  fi
  local meta params
  meta="$(jq -cn --arg name "${title}" '{name: $name}')"
  # supportsAllDrives: without it Drive answers 404 for a doc that lives in a shared drive.
  params="$(jq -cn --arg id "${doc}" --arg f "${REPLY_FIELDS}" '{fileId: $id, fields: $f, supportsAllDrives: true}')"
  gws drive files update "${flags[@]}" --json "${meta}" --upload body.md --upload-content-type text/markdown --params "${params}" > "${reply_file}"
  echo "updated"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}gdoc_publish${c_rst} — publish a markdown draft as a finished Google Doc (create or update in place)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file DRAFT.md [OPTIONS]

${c_bold}Options:${c_rst}
  --file DRAFT.md    Markdown draft; first line is the title unless --title is given (required)
  --title TITLE      Doc title; keeps the whole file as body
  --doc ID_OR_URL    Update this existing Doc in place (replaces its whole body)
  --folder ID_OR_URL Create the Doc inside this Drive folder (id or drive.google.com/drive/folders URL); not with --doc
  --dry-run          Validate the Drive request; create/update nothing
  -h, --help         Show this help

${c_bold}Output:${c_rst} the Doc URL on stdout. Non-zero exit after "Doc created" means finishing failed
(e.g. an image taller than one page); fix the draft and re-run with --doc URL.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local file="" title="" doc="" folder="" dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --file)     file="${2:?--file requires a value}"; shift 2 ;;
    --title)    title="${2:?--title requires a value}"; shift 2 ;;
    --doc)      doc="${2:?--doc requires a value}"; shift 2 ;;
    --folder)   folder="${2:?--folder requires a value}"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  doc="$(doc_id_from "${doc}")"
  folder="$(folder_id_from "${folder}")"
  [[ -n "${file}" ]] && file="${file:A}"

  # === VALIDATE ===
  [[ -n "${file}" ]] || { log::err "Missing --file"; help; return 1; }
  [[ -f "${file}" ]] || { log::err "Draft not found | file='${file}'"; return 1; }
  if [[ -n "${folder}" && -n "${doc}" ]]; then
    log::err "An existing Doc is not moved; pass one of the two | doc='${doc}' folder='${folder}'"
    return 1
  fi

  # === LOGIC ===
  # gws refuses --upload paths outside the cwd, so stage the body in a temp dir and cd there.
  local work
  work="$(mktemp -d /tmp/gdoc_publish.XXXXXX)"
  title="$(stage_body "${file}" "${title}" "${work}/body.md")"
  if [[ -z "${title}" ]]; then
    log::err "Empty title | file='${file}'"
    return 1
  fi
  if [[ "${title}" == "#"* ]]; then
    log::err "Title line must be plain text, not a heading | title='${title}'"
    return 1
  fi
  log::info "Staged body | title='${title}' body='${work}/body.md' bytes='$(wc -c < "${work}/body.md" | tr -d ' ')'"

  local folder_name=""
  if [[ -n "${folder}" ]]; then
    folder_name="$(resolve_folder "${folder}" "${work}/folder_reply.json")" || return 1
    log::info "Target folder | folder='${folder}' name='${folder_name}' drive='$(jq -r '.driveId // "my-drive"' "${work}/folder_reply.json")'"
  fi

  cd "${work}"
  local action
  action="$(upload_doc "${title}" "${doc}" "${folder}" "${dry_run}" "${work}/drive_reply.json")"
  if [[ "${dry_run}" == "true" ]]; then
    log::ok "Dry run valid | action='${action}' folder='${folder}' folder_name='${folder_name}' reply='${work}/drive_reply.json'"
    return 0
  fi

  local doc_id
  doc_id="$(jq -r '.id // empty' "${work}/drive_reply.json")"
  if [[ -z "${doc_id}" ]]; then
    log::err "Drive reply has no id | reply='${work}/drive_reply.json'"
    return 1
  fi
  local url="https://docs.google.com/document/d/${doc_id}/edit"
  log::ok "Doc ${action} | doc='${doc_id}' url='${url}' parents='$(jq -r '(.parents // []) | join(",")' "${work}/drive_reply.json")'"

  local finish_rc=0
  zsh "${SCRIPT_DIR}/gdoc_finish.zsh" --doc "${doc_id}" || finish_rc=$?
  log::info "Manual step remains: Format > Table > Pin header row (tableHeader is read-only in the Docs API)"
  echo "${url}"
  return "${finish_rc}"
}

main "${@}"
