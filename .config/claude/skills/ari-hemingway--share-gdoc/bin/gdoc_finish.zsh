#!/usr/bin/env zsh
# Finish a Google Doc created from markdown in one fix-up batch: convert every plain Drive link
# into a smart chip, style every table's header row (bold, centered, grey #D9D9D9), and set each
# two-column table's column widths to the split that makes it shortest, then verify
# from one re-read that every inline image fits one page and links to its editable mermaid.live
# source and that no plain Drive link remains. tableHeader (pin header row) is read-only in the
# Docs API and stays a manual step.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Constants ---

readonly HEADER_GREY="0.8509804"   # #D9D9D9, matches Docs' "light grey 1"
# tabs.* cannot share a field mask with body.content, so only the first tab is processed.
readonly GET_FIELDS="revisionId,documentStyle,inlineObjects,body.content"
# A diagram image must open its editable source; the markdown form [![alt](ink)](live) lands here.
readonly IMAGE_LINK_PREFIX="https://mermaid.live/edit#"
# Drive's markdown import lands a raw Drive URL as a plain hyperlink; insertRichLink (Docs API,
# April 2026) turns it into a chip. It accepts Drive file and folder URLs only, so this is the
# whole allowlist; the captured id is what the pre-flight files.get validates.
readonly DRIVE_LINK_RE='^https://(docs|drive)\.google\.com/(.*/d/|drive/folders/)([A-Za-z0-9_-]+)'
# Column-width model for two-column tables: Arial metrics plus greedy wrap, see the jq header.
readonly TABLE_WIDTHS_JQ="${SCRIPT_DIR:h}/lib/table_widths.jq"

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

#######################################
# Fetch the doc JSON the checks and requests are built from.
# Globals: GET_FIELDS
# Arguments: $1 - doc id, $2 - output path
#######################################
fetch_doc() {
  local doc="${1}" out="${2}"
  local params
  params="$(jq -cn --arg id "${doc}" --arg f "${GET_FIELDS}" '{documentId: $id, fields: $f}')"
  gws docs documents get --params "${params}" --format json > "${out}"
}

#######################################
# Run one batchUpdate pinned to the revision the requests were built from, or validate it
# locally under --dry-run.
# Arguments: $1 - doc id, $2 - requests JSON array path, $3 - revision id, $4 - dry_run (true|false), $5 - reply path
#######################################
batch_update() {
  local doc="${1}" requests="${2}" revision="${3}" dry_run="${4}" reply="${5}"
  local params body
  params="$(jq -cn --arg id "${doc}" '{documentId: $id}')"
  body="$(jq -c --arg rev "${revision}" '{requests: ., writeControl: {requiredRevisionId: $rev}}' "${requests}")"
  if [[ "${dry_run}" == "true" ]]; then
    gws docs documents batchUpdate --dry-run --params "${params}" --json "${body}" > "${reply}"
    return
  fi
  gws docs documents batchUpdate --params "${params}" --json "${body}" > "${reply}"
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
    [.. | objects | select(.inlineObjectElement != null)]
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
# List every plain Drive hyperlink as {start, end, url, file_id}, one entry per link, anywhere in
# the body including table cells. Adjacent runs that share a URL are one link; a run's trailing
# newline is excluded so deleting the text keeps the paragraph.
# Globals: DRIVE_LINK_RE
# Arguments: $1 - path to doc JSON
# Outputs: JSON array on stdout
#######################################
plain_drive_links() {
  local doc_json="${1}"
  jq -c --arg re "${DRIVE_LINK_RE}" '
    [.. | objects | select(.paragraph != null) | .paragraph.elements
      | reduce .[] as $e ([];
          if ($e.textRun? != null) and (($e.textRun.textStyle.link.url // "") | test($re)) then
            ($e.textRun.textStyle.link.url) as $u
            | (if ($e.textRun.content | endswith("\n")) then $e.endIndex - 1 else $e.endIndex end) as $end
            | if (length > 0) and (.[-1].url == $u) and (.[-1].end == $e.startIndex)
              then .[:-1] + [ .[-1] + {end: $end} ]
              else . + [{start: $e.startIndex, end: $end, url: $u, file_id: ($u | match($re).captures[2].string)}] end
          else . end)
      | .[]]' "${doc_json}"
}

#######################################
# Drop links whose target the caller cannot read: insertRichLink fails with "Error fetching chip
# data" for those, and one failing request rolls back the whole batch.
# Arguments: $1 - links JSON array path, $2 - output path for the validated array
#######################################
validate_link_targets() {
  local links="${1}" out="${2}"
  local file_id url
  local -a keep
  keep=()
  while IFS=$'\t' read -r file_id url; do
    [[ -n "${file_id}" ]] || continue
    if gws drive files get --params "$(jq -cn --arg id "${file_id}" '{fileId: $id, fields: "id", supportsAllDrives: true}')" >/dev/null 2>&1; then
      keep+=("${file_id}")
    else
      log::warn "Drive link target unreadable; left as a hyperlink | file_id='${file_id}' url='${url}'"
    fi
  done < <(jq -r '.[] | "\(.file_id)\t\(.url)"' "${links}")
  jq -c --argjson ok "$(printf '%s\n' "${keep[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" '[.[] | select(.file_id as $f | $ok | index($f) != null)]' "${links}" > "${out}"
}

#######################################
# Build the chip requests: delete the link text, then insertRichLink at the same index.
# richLinkProperties carries only uri; the server resolves title and mimeType and rejects both.
# Each request carries an `anchor` for ordering, stripped before sending.
# Arguments: $1 - links JSON array path, $2 - output path for the requests JSON array
#######################################
build_chip_requests() {
  local links="${1}" out="${2}"
  jq -c '[.[]
    | {anchor: .start, order: 0, request: {deleteContentRange: {range: {startIndex: .start, endIndex: .end}}}},
      {anchor: .start, order: 1, request: {insertRichLink: {location: {index: .start}, richLinkProperties: {uri: .url}}}}]' "${links}" > "${out}"
}

#######################################
# Build the header-style requests for every table, each carrying an `anchor` for ordering.
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
        | [ {anchor: $t, order: 2, request: {updateTableCellStyle: {
              tableRange: {tableCellLocation: {tableStartLocation: {index: $t}, rowIndex: 0, columnIndex: 0}, rowSpan: 1, columnSpan: $cols},
              tableCellStyle: {backgroundColor: {color: {rgbColor: {red: $grey, green: $grey, blue: $grey}}}},
              fields: "backgroundColor"}}} ]
          + [$paras[] | {anchor: .startIndex, order: 2, request: {updateParagraphStyle: {range: {startIndex: .startIndex, endIndex: .endIndex}, paragraphStyle: {alignment: "CENTER"}, fields: "alignment"}}}]
          + [$paras[] | select(.endIndex - .startIndex > 1) | {anchor: .startIndex, order: 2, request: {updateTextStyle: {range: {startIndex: .startIndex, endIndex: (.endIndex - 1)}, textStyle: {bold: true}, fields: "bold"}}}]
      )
    | add // []' "${doc_json}" > "${out}"
}

#######################################
# Build the column-width requests for every two-column table whose modeled height improves:
# both columns become FIXED_WIDTH at the split the model found. Logs the model's line counts
# before and after per table. Each request carries an `anchor` for ordering.
# Globals: TABLE_WIDTHS_JQ
# Arguments: $1 - path to doc JSON, $2 - output path for the requests JSON array
#######################################
build_column_width_requests() {
  local doc_json="${1}" out="${2}"
  local plan
  plan="$(jq -c -f "${TABLE_WIDTHS_JQ}" "${doc_json}")"
  local start rows cw0 cw1 clines bw0 bw1 blines
  while IFS=$'\t' read -r start rows cw0 cw1 clines bw0 bw1 blines; do
    [[ -n "${start}" ]] || continue
    if (( blines < clines )); then
      log::info "Table columns resized | start='${start}' rows='${rows}' current='${cw0}/${cw1} pt, ${clines} lines' best='${bw0}/${bw1} pt, ${blines} lines'"
    else
      log::info "Table columns kept | start='${start}' rows='${rows}' widths='${cw0}/${cw1} pt' lines='${clines}'"
    fi
  done < <(print -r -- "${plan}" | jq -r '.[] | [.start, .rows, (.current.w0|round), (.current.w1|round), .current.lines, .best.w0, .best.w1, .best.lines] | @tsv')
  print -r -- "${plan}" | jq -c '[.[] | select(.best.lines < .current.lines) | .start as $t
    | ({col: 0, w: .best.w0}, {col: 1, w: .best.w1})
    | {anchor: $t, order: 2, request: {updateTableColumnProperties: {
        tableStartLocation: {index: $t}, columnIndices: [.col],
        tableColumnProperties: {widthType: "FIXED_WIDTH", width: {magnitude: .w, unit: "PT"}},
        fields: "widthType,width"}}}]' > "${out}"
}

#######################################
# Merge chip, style, and width requests into the one batch. Descending anchor order means every
# request runs before anything that would shift its indexes; within one anchor a link's delete
# precedes its insert, and styles come last.
# Arguments: $1 - chip requests path, $2 - style requests path, $3 - width requests path, $4 - output path for the plain requests array
#######################################
merge_requests() {
  local chips="${1}" styles="${2}" widths="${3}" out="${4}"
  jq -cs '.[0] + .[1] + .[2] | sort_by([-.anchor, .order]) | map(.request)' "${chips}" "${styles}" "${widths}" > "${out}"
}

#######################################
# Log one line per remaining plain Drive link; the fix-up batch should have left none.
# Arguments: $1 - path to doc JSON
# Returns: 1 if any plain Drive link remains
#######################################
check_drive_links_are_chips() {
  local doc_json="${1}"
  local n_chips n_plain
  n_chips="$(jq '[.. | objects | select(.richLink != null)] | length' "${doc_json}")"
  n_plain="$(plain_drive_links "${doc_json}" | jq 'length')"
  if (( n_plain == 0 )); then
    log::ok "Every Drive link is a chip | chips='${n_chips}'"
    return 0
  fi
  plain_drive_links "${doc_json}" | jq -r '.[] | "\(.start)\t\(.url)"' | while IFS=$'\t' read -r start url; do
    log::err "Drive link is not a chip | index='${start}' url='${url}'"
  done
  return 1
}

#######################################
# Log the doc's rendered page count: export to PDF and read /Count from the Pages root. This is
# the one real layout measurement available (the Docs API reports no geometry), so it is what
# the column-width model is judged against.
# Arguments: $1 - doc id, $2 - work dir
#######################################
report_page_count() {
  local doc="${1}" work="${2}"
  local params pages
  params="$(jq -cn --arg id "${doc}" '{fileId: $id, mimeType: "application/pdf"}')"
  # gws saves the export as download.pdf in the working directory.
  (cd "${work}" && gws drive files export --params "${params}" > "${work}/export_reply.json") || { log::warn "PDF export failed; page count unknown | doc='${doc}'"; return 0; }
  pages="$(strings -n 3 "${work}/download.pdf" | grep -A1 '/Type /Pages' | grep -oE '/Count +[0-9]+' | head -1 | tr -dc '0-9')"
  if [[ -z "${pages}" ]]; then
    log::warn "PDF export unreadable; page count unknown | pdf='${work}/download.pdf'"
    return 0
  fi
  log::info "Rendered length | pages='${pages}' pdf='${work}/download.pdf'"
  # Per-table rendered heights from the same PDF, so a column-width change can be judged in points.
  local table pages_on rows cols height content
  while IFS=$'\t' read -r table pages_on rows cols height content; do
    [[ -n "${table}" ]] || continue
    log::info "Rendered table | table='${table}' pages='${pages_on}' rows='${rows}' cols='${cols}' height_pt='${height}' content_height_pt='${content}'"
  done < <(zsh "${SCRIPT_DIR}/gdoc_table_heights.zsh" --pdf "${work}/download.pdf" 2>/dev/null \
           | jq -r '[.table, (.pages | join(",")), .rows, .cols, .height_pt, .content_height_pt] | @tsv')
}

#######################################
# Run every check against one doc JSON, then report the rendered page count.
# Arguments: $1 - path to doc JSON, $2 - doc id, $3 - work dir
# Returns: 1 if any check fails
#######################################
run_checks() {
  local doc_json="${1}" doc="${2}" work="${3}"
  local rc=0
  check_images_fit_one_page "${doc_json}" || rc=1
  check_images_link_to_source "${doc_json}" || rc=1
  check_drive_links_are_chips "${doc_json}" || rc=1
  report_page_count "${doc}" "${work}"
  return "${rc}"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}gdoc_finish${c_rst} — one fix-up batch (Drive links to chips, styled table headers, two-column tables at their shortest split), then one verify read

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc ID_OR_URL [OPTIONS]

${c_bold}Options:${c_rst}
  --doc ID_OR_URL   Google Doc id or docs.google.com URL (required)
  --check-only      Run the checks against the doc as it is; change nothing
  --dry-run         Validate the fix-up batch locally; change nothing
  -h, --help        Show this help

${c_bold}Exit code:${c_rst} non-zero when any inline image exceeds the page content box or lacks a link to its
mermaid.live source, or when any Drive link is still a plain hyperlink.
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
  fetch_doc "${doc}" "${work}/doc.json"
  log::info "Fetched doc | doc='${doc}' json='${work}/doc.json'"

  if [[ "${check_only}" == "true" ]]; then
    run_checks "${work}/doc.json" "${doc}" "${work}"
    return
  fi

  # One batch built from the one read: chips and header styles together.
  plain_drive_links "${work}/doc.json" > "${work}/links.json"
  validate_link_targets "${work}/links.json" "${work}/links.valid.json"
  build_chip_requests "${work}/links.valid.json" "${work}/chip_requests.json"
  build_header_style_requests "${work}/doc.json" "${work}/style_requests.json"
  build_column_width_requests "${work}/doc.json" "${work}/width_requests.json"
  merge_requests "${work}/chip_requests.json" "${work}/style_requests.json" "${work}/width_requests.json" "${work}/requests.json"
  local n_links n_tables n_requests revision
  n_links="$(jq 'length' "${work}/links.valid.json")"
  n_tables="$(jq '[.body.content[] | select(.table)] | length' "${work}/doc.json")"
  n_requests="$(jq 'length' "${work}/requests.json")"
  revision="$(jq -r '.revisionId' "${work}/doc.json")"
  log::info "Built fix-up batch | links='${n_links}' tables='${n_tables}' requests='${n_requests}' file='${work}/requests.json'"

  if (( n_requests > 0 )); then
    batch_update "${doc}" "${work}/requests.json" "${revision}" "${dry_run}" "${work}/batch_reply.json"
    if [[ "${dry_run}" == "true" ]]; then
      log::ok "Fix-up batch dry run valid | out='${work}/batch_reply.json'"
      log::info "Checks run against the unchanged doc under --dry-run"
    else
      log::ok "Applied fix-up batch | links='${n_links}' tables='${n_tables}' out='${work}/batch_reply.json'"
      fetch_doc "${doc}" "${work}/doc.json"
    fi
  else
    log::info "Nothing to fix up"
  fi

  run_checks "${work}/doc.json" "${doc}" "${work}"
}

main "${@}"
