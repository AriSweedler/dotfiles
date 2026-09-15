#!/usr/bin/env zsh
# Finish a Google Doc created from markdown: style every table's header row (bold,
# centered, grey #D9D9D9), verify every inline image fits inside one page, and verify
# every inline image links to its editable mermaid.live source.
# tableHeader (pin header row) is read-only in the Docs API and stays a manual step.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Constants ---

readonly HEADER_GREY="0.8509804"   # #D9D9D9, matches Docs' "light grey 1"
readonly GET_FIELDS="documentStyle,inlineObjects,body.content"
# A diagram image must open its editable source; the markdown form [![alt](ink)](live) lands here.
readonly IMAGE_LINK_PREFIX="https://mermaid.live/edit#"

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

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

########################################################################
# Business logic
########################################################################

#######################################
# Log one line per inline image saying whether it fits the page content box.
# Arguments: $1 - path to doc JSON
# Returns: 1 if any image exceeds the box
#######################################
check_images_fit_one_page() {
  local doc_json="${1}"
  local rc=0 id w h maxw maxh verdict
  local tsv
  tsv="$(jq -r '
    .documentStyle as $ds
    | ($ds.pageSize.height.magnitude - $ds.marginTop.magnitude - $ds.marginBottom.magnitude) as $maxH
    | ($ds.pageSize.width.magnitude - $ds.marginLeft.magnitude - $ds.marginRight.magnitude) as $maxW
    | (.inlineObjects // {}) | to_entries[]
    | .value.inlineObjectProperties.embeddedObject.size as $s
    | [.key, $s.width.magnitude, $s.height.magnitude, $maxW, $maxH,
       (if $s.width.magnitude <= $maxW and $s.height.magnitude <= $maxH then "OK" else "FAIL" end)]
    | @tsv' "${doc_json}")"
  if [[ -z "${tsv}" ]]; then
    log::info "No inline images in doc"
    return 0
  fi
  while IFS=$'\t' read -r id w h maxw maxh verdict; do
    if [[ "${verdict}" == "OK" ]]; then
      log::ok "Image fits one page | id='${id}' width_pt='${w}' height_pt='${h}' max_width_pt='${maxw}' max_height_pt='${maxh}'"
      continue
    fi
    log::err "Image exceeds one page | id='${id}' width_pt='${w}' height_pt='${h}' max_width_pt='${maxw}' max_height_pt='${maxh}'"
    rc=1
  done <<< "${tsv}"
  return "${rc}"
}

#######################################
# Log one line per inline image saying whether it links to its mermaid.live source.
# Globals: IMAGE_LINK_PREFIX
# Arguments: $1 - path to doc JSON
# Returns: 1 if any image has no link or a link outside mermaid.live
#######################################
check_images_link_to_source() {
  local doc_json="${1}"
  local rc=0 id url verdict
  local tsv
  tsv="$(jq -r --arg prefix "${IMAGE_LINK_PREFIX}" '
    [.body.content[] | .paragraph? | select(. != null) | .elements[] | select(.inlineObjectElement != null)]
    | .[]
    | (.inlineObjectElement.textStyle.link.url // "") as $url
    | [.inlineObjectElement.inlineObjectId, $url, (if ($url | startswith($prefix)) then "OK" else "FAIL" end)]
    | @tsv' "${doc_json}")"
  if [[ -z "${tsv}" ]]; then
    log::info "No inline images in doc"
    return 0
  fi
  while IFS=$'\t' read -r id url verdict; do
    if [[ "${verdict}" == "OK" ]]; then
      log::ok "Image links to its source | id='${id}' url='${url:0:60}...'"
      continue
    fi
    log::err "Image does not link to its mermaid.live source | id='${id}' url='${url}' expected_prefix='${IMAGE_LINK_PREFIX}'"
    rc=1
  done <<< "${tsv}"
  return "${rc}"
}

#######################################
# Build the batchUpdate requests that style every table's header row.
# Arguments: $1 - path to doc JSON, $2 - output path for the requests JSON array
#######################################
build_header_style_requests() {
  local doc_json="${1}" out="${2}"
  jq -c --argjson grey "${HEADER_GREY}" '
    [.body.content[] | select(.table)]
    | map(
        .startIndex as $t
        | .table.columns as $cols
        | [.table.tableRows[0].tableCells[].content[] | select(.paragraph) | {startIndex, endIndex}] as $paras
        | [ {updateTableCellStyle: {
              tableRange: {tableCellLocation: {tableStartLocation: {index: $t}, rowIndex: 0, columnIndex: 0}, rowSpan: 1, columnSpan: $cols},
              tableCellStyle: {backgroundColor: {color: {rgbColor: {red: $grey, green: $grey, blue: $grey}}}},
              fields: "backgroundColor"}} ]
          + [$paras[] | {updateParagraphStyle: {range: {startIndex: .startIndex, endIndex: .endIndex}, paragraphStyle: {alignment: "CENTER"}, fields: "alignment"}}]
          + [$paras[] | select(.endIndex - .startIndex > 1) | {updateTextStyle: {range: {startIndex: .startIndex, endIndex: (.endIndex - 1)}, textStyle: {bold: true}, fields: "bold"}}]
      )
    | add // []' "${doc_json}" > "${out}"
}

#######################################
# Apply or dry-run the header styling.
# Arguments: $1 - doc id, $2 - requests JSON path, $3 - dry_run (true|false), $4 - work dir
#######################################
apply_header_style() {
  local doc="${1}" requests="${2}" dry_run="${3}" work="${4}"
  local params body
  params="$(jq -cn --arg id "${doc}" '{documentId: $id}')"
  body="$(jq -c '{requests: .}' "${requests}")"
  if [[ "${dry_run}" == "true" ]]; then
    gws docs documents batchUpdate --dry-run --params "${params}" --json "${body}" > "${work}/batch_dry_run.json"
    log::ok "Dry run valid | out='${work}/batch_dry_run.json'"
    return
  fi
  gws docs documents batchUpdate --params "${params}" --json "${body}" > "${work}/batch_reply.json"
  log::ok "Styled header rows | out='${work}/batch_reply.json'"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}gdoc_finish${c_rst} — style table header rows; check images fit one page and link to their mermaid.live source

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc ID_OR_URL [OPTIONS]

${c_bold}Options:${c_rst}
  --doc ID_OR_URL   Google Doc id or docs.google.com URL (required)
  --check-only      Report images and would-be styling; change nothing
  --dry-run         Validate the styling request locally; change nothing
  -h, --help        Show this help

${c_bold}Exit code:${c_rst} non-zero when any inline image exceeds the page content box or lacks a link to its mermaid.live source.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local doc="" check_only=false dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)    help; return 0 ;;
    --doc)        doc="${2:?--doc requires a value}"; shift 2 ;;
    --check-only) check_only=true; shift ;;
    --dry-run)    dry_run=true; shift ;;
    -*)           log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)            log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  doc="$(doc_id_from "${doc}")"

  # === VALIDATE ===
  [[ -n "${doc}" ]] || { log::err "Missing --doc"; help; return 1; }

  # === LOGIC ===
  local work
  work="$(mktemp -d /tmp/gdoc_finish.XXXXXX)"
  local params
  params="$(jq -cn --arg id "${doc}" --arg f "${GET_FIELDS}" '{documentId: $id, fields: $f}')"
  gws docs documents get --params "${params}" --format json > "${work}/doc.json"
  log::info "Fetched doc | doc='${doc}' json='${work}/doc.json'"

  local image_rc=0
  check_images_fit_one_page "${work}/doc.json" || image_rc=1
  check_images_link_to_source "${work}/doc.json" || image_rc=1

  build_header_style_requests "${work}/doc.json" "${work}/requests.json"
  local n_tables n_requests
  n_tables="$(jq '[.body.content[] | select(.table)] | length' "${work}/doc.json")"
  n_requests="$(jq 'length' "${work}/requests.json")"
  log::info "Built header-style requests | tables='${n_tables}' requests='${n_requests}' file='${work}/requests.json'"

  if [[ "${check_only}" == "true" ]]; then
    log::info "Check-only: not applying styles"
    return "${image_rc}"
  fi
  if (( n_requests == 0 )); then
    log::info "No tables to style"
    return "${image_rc}"
  fi
  apply_header_style "${doc}" "${work}/requests.json" "${dry_run}" "${work}"
  return "${image_rc}"
}

main "${@}"
