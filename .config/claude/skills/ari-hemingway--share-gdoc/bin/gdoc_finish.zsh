#!/usr/bin/env zsh
# Finish a Google Doc created from markdown in one fix-up batch: convert every plain Drive link
# into a smart chip, style every table's header row (bold, centered, grey #D9D9D9), and set every
# table's column widths to the ones that make it shortest with no column narrower than its widest
# token, then verify from one re-read that every inline image fits one page and links to its
# mermaid.live source in fullscreen view, that no plain Drive link remains, that every table fits the text
# width, and that every table's first row is a pinned header (Drive's markdown import sets
# tableHeader; the PDF export repeats that row on every page).

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Constants ---

readonly HEADER_GREY="0.8509804"   # #D9D9D9, matches Docs' "light grey 1"
# tabs.* cannot share a field mask with body.content, so only the first tab is processed.
readonly GET_FIELDS="revisionId,documentStyle,inlineObjects,body.content"
# A diagram image must open its source fullscreen (/view, not /edit: the reader gets the diagram,
# not the editor); the markdown form [![alt](ink)](live) lands here.
readonly IMAGE_LINK_PREFIX="https://mermaid.live/view#"
# Drive's markdown import lands a raw Drive URL as a plain hyperlink; insertRichLink (Docs API,
# April 2026) turns it into a chip. It accepts Drive file and folder URLs only, so this is the
# whole allowlist; the captured id is what the pre-flight files.get validates.
readonly DRIVE_LINK_RE='^https://(docs|drive)\.google\.com/(.*/d/|drive/folders/)([A-Za-z0-9_-]+)'
# Column-width planner for every table (any column count): Arial metrics plus greedy wrap, hard
# minimum per column at its widest token; see the Python header. Points per modeled line, for
# the predicted-vs-rendered comparison, match the planner's LINE_HEIGHT_PT.
readonly TABLE_WIDTHS="${SCRIPT_DIR}/gdoc_table_widths.zsh"
readonly LINE_HEIGHT_PT="15.15"
# A rendered table may drift from the model by this much before the verify read warns: 1.5 lines,
# because a single extra wrapped line is model rounding, not a layout problem worth a look.
readonly DRIFT_TOLERANCE_PT="22.7"

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
  local cmd
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
  local doc="${1}" requests="${2}" revision="${3}" dry_run="${4}" reply_file="${5}"
  local params body
  params="$(jq -cn --arg id "${doc}" '{documentId: $id}')"
  body="$(jq -c --arg rev "${revision}" '{requests: ., writeControl: {requiredRevisionId: $rev}}' "${requests}")"
  if [[ "${dry_run}" == "true" ]]; then
    gws docs documents batchUpdate --dry-run --params "${params}" --json "${body}" > "${reply_file}"
    return
  fi
  gws docs documents batchUpdate --params "${params}" --json "${body}" > "${reply_file}"
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
# Returns: 1 if any image has no link or a link that is not the mermaid.live view form
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
# Run the width planner over every table in the doc; one JSON line per table into the plan file.
# Globals: TABLE_WIDTHS
# Arguments: $1 - path to doc JSON, $2 - output path for the plan (JSON lines), $@ - width overrides (START:w1,w2,...)
#######################################
plan_table_widths() {
  local doc_json="${1}" out="${2}"
  shift 2
  local -a override_flags
  override_flags=()
  local spec
  for spec in "${@}"; do override_flags+=(--override "${spec}"); done
  zsh "${TABLE_WIDTHS}" --doc-json "${doc_json}" "${override_flags[@]}" > "${out}"
}

#######################################
# Build the column-width requests from the plan: every column of every feasible table whose
# modeled line count improves (or that the caller overrode) becomes FIXED_WIDTH at the planned
# width. Logs one line per table. Each request carries an `anchor` for ordering.
# Arguments: $1 - path to the plan (JSON lines), $2 - output path for the requests JSON array
#######################################
build_column_width_requests() {
  local plan="${1}" out="${2}"
  local start rows cols current clines best blines feasible source
  while IFS=$'\t' read -r start rows cols current clines best blines feasible source; do
    [[ -n "${start}" ]] || continue
    if [[ "${feasible}" != "true" ]]; then
      log::warn "Table columns left as is; it cannot fit | start='${start}' rows='${rows}' cols='${cols}'"
    elif [[ "${source}" == "override" ]]; then
      log::info "Table columns overridden | start='${start}' rows='${rows}' cols='${cols}' widths='${best} pt' lines='${blines}'"
    elif (( blines < clines )); then
      log::info "Table columns resized | start='${start}' rows='${rows}' cols='${cols}' current='${current} pt, ${clines} lines' best='${best} pt, ${blines} lines'"
    else
      log::info "Table columns kept | start='${start}' rows='${rows}' cols='${cols}' widths='${current} pt' lines='${clines}'"
    fi
  done < <(jq -r '[.start, .rows, .cols, (.current_pt | map(round) | join("/")), .current_lines, ((.best_pt // []) | map(round) | join("/")), (.best_lines // 0), .feasible, .source] | @tsv' "${plan}")
  jq -cs '[.[] | select(.feasible and (.source == "override" or .best_lines < .current_lines)) | .start as $t
    | .best_pt | to_entries[]
    | {anchor: $t, order: 2, request: {updateTableColumnProperties: {
        tableStartLocation: {index: $t}, columnIndices: [.key],
        tableColumnProperties: {widthType: "FIXED_WIDTH", width: {magnitude: .value, unit: "PT"}},
        fields: "widthType,width"}}}]' "${plan}" > "${out}"
}

#######################################
# Log whether every table's first row is a pinned header (tableRowStyle.tableHeader). Drive's
# markdown import sets it, and Docs repeats a pinned row on every page the table spans.
# Arguments: $1 - path to doc JSON
# Returns: 1 if any table's first row is not pinned
#######################################
check_header_rows_pinned() {
  local doc_json="${1}"
  local rc=0 start n_tables
  n_tables="$(jq '[.body.content[] | select(.table)] | length' "${doc_json}")"
  while IFS=$'\t' read -r start; do
    [[ -n "${start}" ]] || continue
    log::warn "Table header row is not pinned | start='${start}' expected='tableRows[0].tableRowStyle.tableHeader == true'"
    rc=1
  done < <(jq -r '.body.content[] | select(.table) | select((.table.tableRows[0].tableRowStyle.tableHeader // false) | not) | [.startIndex] | @tsv' "${doc_json}")
  if (( rc == 0 )); then
    log::ok "Header rows pinned | tables='${n_tables}'"
  fi
  return "${rc}"
}

#######################################
# Log one line per table that cannot fit the text width even at its columns' minimums, naming the
# deficit and the widest token per column; the author folds a column or shortens a token.
# Arguments: $1 - path to the plan (JSON lines)
# Returns: 1 if any table cannot fit
#######################################
check_tables_fit() {
  local plan="${1}"
  local rc=0 start cols deficit widest
  while IFS=$'\t' read -r start cols deficit widest; do
    [[ -n "${start}" ]] || continue
    log::err "Table cannot fit the text width | start='${start}' cols='${cols}' deficit_pt='${deficit}' widest_tokens='${widest}' fix='fold a column or shorten a token, then re-run with --doc'"
    rc=1
  done < <(jq -r 'select(.feasible | not) | [.start, .cols, .deficit_pt, (.widest_tokens | join(" | "))] | @tsv' "${plan}")
  if (( rc == 0 )); then
    log::ok "Every table fits the text width | tables='$(jq -s 'length' "${plan}")'"
  fi
  return "${rc}"
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
# the column-width model is judged against: each table's rendered height is compared with the
# planner's prediction for the widths the doc now has, and a drift over DRIFT_TOLERANCE_PT warns.
# Globals: DRIFT_TOLERANCE_PT
# Arguments: $1 - doc id, $2 - work dir, $3 - path to the plan for the doc as it now is (JSON lines)
#######################################
report_page_count() {
  local doc="${1}" work="${2}" plan="${3}"
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
  # Per-table rendered heights from the same PDF, matched to the plan by document order.
  local table pages_on rows cols height content predicted drift
  while IFS=$'\t' read -r table pages_on rows cols height content; do
    [[ -n "${table}" ]] || continue
    predicted="$(jq -rs --argjson n "${table}" '.[$n - 1].predicted_current_pt // empty' "${plan}")"
    if [[ -z "${predicted}" ]]; then
      log::info "Rendered table | table='${table}' pages='${pages_on}' rows='${rows}' cols='${cols}' height_pt='${height}' content_height_pt='${content}'"
      continue
    fi
    drift="$(awk -v a="${content}" -v b="${predicted}" 'BEGIN { d = a - b; if (d < 0) d = -d; printf "%.1f", d }')"
    if awk -v d="${drift}" -v tol="${DRIFT_TOLERANCE_PT}" 'BEGIN { exit !(d > tol) }'; then
      log::warn "Rendered table drifts from the model | table='${table}' pages='${pages_on}' rows='${rows}' cols='${cols}' content_height_pt='${content}' predicted_pt='${predicted}' drift_pt='${drift}' tolerance_pt='${DRIFT_TOLERANCE_PT}'"
      continue
    fi
    log::info "Rendered table | table='${table}' pages='${pages_on}' rows='${rows}' cols='${cols}' height_pt='${height}' content_height_pt='${content}' predicted_pt='${predicted}' drift_pt='${drift}'"
  done < <(zsh "${SCRIPT_DIR}/gdoc_table_heights.zsh" --pdf "${work}/download.pdf" 2>/dev/null \
           | jq -r '[.table, (.pages | join(",")), .rows, .cols, .height_pt, .content_height_pt] | @tsv')
}

#######################################
# Render every page of the exported PDF to PNG when the caller asked for it.
# Arguments: $1 - work dir (holds download.pdf), $2 - output dir ("" = skip)
#######################################
render_pages_if_requested() {
  local work="${1}" out="${2}"
  if [[ -z "${out}" ]]; then
    return 0
  fi
  if [[ ! -f "${work}/download.pdf" ]]; then
    log::warn "No PDF export to render | work='${work}'"
    return 0
  fi
  zsh "${SCRIPT_DIR}/gdoc_render_pages.zsh" --pdf "${work}/download.pdf" --out "${out}" > /dev/null
}

#######################################
# Run every check against one doc JSON (planning table widths read-only for the fit check and the
# height comparison), then report the rendered page count.
# Arguments: $1 - path to doc JSON, $2 - doc id, $3 - work dir, $4 - page render dir ("" = skip)
# Returns: 1 if any check fails
#######################################
run_checks() {
  local doc_json="${1}" doc="${2}" work="${3}" render_dir="${4}"
  local rc=0
  check_images_fit_one_page "${doc_json}" || rc=1
  check_images_link_to_source "${doc_json}" || rc=1
  check_drive_links_are_chips "${doc_json}" || rc=1
  check_header_rows_pinned "${doc_json}" || rc=1
  plan_table_widths "${doc_json}" "${work}/plan_after.json"
  check_tables_fit "${work}/plan_after.json" || rc=1
  report_page_count "${doc}" "${work}" "${work}/plan_after.json"
  render_pages_if_requested "${work}" "${render_dir}"
  return "${rc}"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}gdoc_finish${c_rst} — one fix-up batch (Drive links to chips, styled table headers, every table at the column widths that make it shortest without mid-word breaks), then one verify read

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc ID_OR_URL [OPTIONS]

${c_bold}Options:${c_rst}
  --doc ID_OR_URL              Google Doc id or docs.google.com URL (required)
  --table-widths START:w1,w2   Widths in points for the table at index START, instead of the model (repeatable; logged)
  --render-pages DIR           Also render the PDF export to one PNG per page in DIR (needs swift)
  --check-only                 Run the checks against the doc as it is; change nothing
  --dry-run                    Validate the fix-up batch locally; change nothing
  -h, --help                   Show this help

${c_bold}Exit code:${c_rst} non-zero when any inline image exceeds the page content box or lacks a link to its
mermaid.live source in view form (${IMAGE_LINK_PREFIX}), when any Drive link is still a plain hyperlink, when a table's first row is not a
pinned header, or when a table's widest tokens cannot fit the text width even at their minimum column
widths (fold a column or shorten a token).
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local doc="" check_only=false dry_run=false render_dir=""
  local -a table_widths
  table_widths=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)       help; return 0 ;;
    --doc)           doc="${2:?--doc requires a value}"; shift 2 ;;
    --table-widths)  table_widths+=("${2:?--table-widths requires a value}"); shift 2 ;;
    --render-pages)  render_dir="${2:?--render-pages requires a value}"; shift 2 ;;
    --check-only)    check_only=true; shift ;;
    --dry-run)       dry_run=true; shift ;;
    -*)              log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)               log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  doc="$(doc_id_from "${doc}")"
  [[ -n "${render_dir}" ]] && render_dir="${render_dir:A}"

  # === VALIDATE ===
  [[ -n "${doc}" ]] || { log::err "Missing --doc"; help; return 1; }
  local spec
  for spec in "${table_widths[@]}"; do
    [[ "${spec}" =~ '^[0-9]+:[0-9.]+(,[0-9.]+)*$' ]] || { log::err "Invalid --table-widths | spec='${spec}' expected='START:w1,w2,...'"; return 1; }
  done
  if [[ -n "${render_dir}" ]] && ! command -v swift >/dev/null 2>&1; then
    log::err "--render-pages needs swift (Xcode command line tools) | render_dir='${render_dir}'"
    return 1
  fi

  # === LOGIC ===
  local work
  work="$(mktemp -d /tmp/gdoc_finish.XXXXXX)"
  fetch_doc "${doc}" "${work}/doc.json"
  log::info "Fetched doc | doc='${doc}' json='${work}/doc.json'"

  if [[ "${check_only}" == "true" ]]; then
    run_checks "${work}/doc.json" "${doc}" "${work}" "${render_dir}"
    return
  fi

  # One batch built from the one read: chips, header styles, and column widths together.
  plain_drive_links "${work}/doc.json" > "${work}/links.json"
  validate_link_targets "${work}/links.json" "${work}/links.valid.json"
  build_chip_requests "${work}/links.valid.json" "${work}/chip_requests.json"
  build_header_style_requests "${work}/doc.json" "${work}/style_requests.json"
  plan_table_widths "${work}/doc.json" "${work}/plan.json" "${table_widths[@]}"
  build_column_width_requests "${work}/plan.json" "${work}/width_requests.json"
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

  run_checks "${work}/doc.json" "${doc}" "${work}" "${render_dir}"
}

main "${@}"
