#!/usr/bin/env zsh
# gdoc_asides.zsh against a fake gws on PATH; no network, no real Doc. It checks:
#   - a diagram line in an aside becomes an inline image in its tab, linked to its mermaid.live view
#   - a mermaid.ink base64: URL over Docs' 2 kB limit is re-encoded as pako: of the same diagram
#   - chips and images in one tab are placed highest index first, one chip per Drive link
#   - code spans are Roboto Mono #188038 outside links and keep the link colour inside one; fenced
#     blocks are Roboto Mono, uncoloured, shaded #F1F3F4
#   - the split refuses every other image, a mermaid fence and an empty fence, by aside number
#   - a rebuild without --execute sends no batch; a marker the rebuild cannot find fails before any is sent
#   - the verify read fails an aside image that is missing, spills the page, or has the wrong link
# Run: zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/tests/gdoc_asides.test.zsh

set -uo pipefail
# A DRY_RUN inherited from the caller's shell would turn every --execute below into a dry run.
unset DRY_RUN

readonly SCRIPT_DIR="${0:A:h}"
readonly ASIDES="${SCRIPT_DIR:h}/bin/gdoc_asides.zsh"
readonly LINK_1="https://mermaid.live/view#pako:aside-one"
readonly LINK_2="https://mermaid.live/view#pako:aside-two"
readonly LINK_3="https://mermaid.live/view#pako:aside-three"
readonly SHORT_INK="https://mermaid.ink/img/base64:eyJjb2RlIjoiQS0tPkIifQ?width=620"
readonly PAKO_PREFIX="https://mermaid.ink/img/pako:"
readonly DOC_A="https://docs.google.com/document/d/DOC_A/edit"
readonly FILE_B="https://drive.google.com/file/d/FILE_B/view"

missing=()
for cmd in jq base64 node; do
  command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
done
if (( ${#missing} > 0 )); then
  print -ru2 -- "[ERROR] missing required commands | missing='${(j:, :)missing}' note='node inflates the pako payload, as bake deflates it'"
  exit 1
fi

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -r -- "ok      ${1}"
  else (( fail += 1 )); print -r -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -r -- "ok      ${1}"
  else (( fail += 1 )); print -r -- "FAIL    ${1} | needle='${2}' haystack='${3:0:300}'"; fi
}

readonly T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin"

# The fake gws: one reply file per call, `<service>-<method>.<n>.json` when present, else
# `<service>-<method>.json`; a batchUpdate body is kept as batch.<n>.json.
cat > "${T}/bin/gws" <<'FAKE'
#!/usr/bin/env zsh
set -euo pipefail
kind="${1}-${3}"
counter="${FAKE_GWS_DIR}/count.${kind}"
typeset -i n=$(( $(cat "${counter}" 2>/dev/null || print 0) + 1 ))
print -r -- "${n}" > "${counter}"
if [[ "${kind}" == "docs-batchUpdate" ]]; then
  print -r -- "${argv[$(( ${argv[(i)--json]} + 1 ))]}" > "${FAKE_GWS_DIR}/batch.${n}.json"
fi
reply="${FAKE_GWS_DIR}/${kind}.${n}.json"
[[ -f "${reply}" ]] || reply="${FAKE_GWS_DIR}/${kind}.json"
cat "${reply}"
FAKE
chmod +x "${T}/bin/gws"

to_base64url() { base64 | tr '+/' '-_' | tr -d '=\n'; }

# A diagram state whose base64: URL is well over 2 kB and deflates far below it, like a baked diagram.
long_state="{\"code\":\"flowchart LR\\n$(repeat 120 print -rn -- 'node_a-->node_b\n')\",\"mermaid\":{\"theme\":\"default\"}}"
readonly LONG_STATE="${long_state}"
readonly LONG_PAYLOAD="$(print -rn -- "${LONG_STATE}" | to_base64url)"
readonly LONG_INK="https://mermaid.ink/img/base64:${LONG_PAYLOAD}?width=620"

cat > "${T}/draft.md" <<EOF
# Intro

See the diagram ([aside 1 ℹ️](#aside-1)) and the build ([aside 2 ℹ️](#aside-2)).

# Useful links

# Aside 1: Architecture

The flow runs \`kubectl\` through [\`gws\`](https://example.com/gws), per [the design](${DOC_A}):

[![Architecture](${LONG_INK})](${LINK_1})

The [\`spec\` doc](${FILE_B}) has the rest; write \`![alt](src)\` to embed one.

# Aside 2: Build

[![Build](${SHORT_INK})](${LINK_2})

\`\`\`
make build
\`\`\`

[![Deploy](${SHORT_INK})](${LINK_3})
EOF

# --- split ---

out="$(zsh "${ASIDES}" --split --file "${T}/draft.md" --body-out "${T}/body.md" 2>"${T}/err")"; rc=$?
check "split of a draft with diagram asides exits 0" 0 "${rc}"
check "split counts both asides" 2 "${out}"
contains "split logs aside 1's image and Drive links" "n='1' title='Architecture' marker='aside 1 ℹ️' blocks='3' body_references='0' drive_links='2' images='1'" "$(cat "${T}/err")"
contains "split logs aside 2's two images" "n='2' title='Build' marker='aside 2 ℹ️' blocks='3' body_references='0' drive_links='0' images='2'" "$(cat "${T}/err")"
check "split leaves no aside in the body" "" "$(awk '/^# Aside|mermaid/' "${T}/body.md")"

split_fails() {   # <name> <needle> <aside body, one or more lines>
  print -r -- "# Intro

([aside 1 ℹ️](#aside-1))

# Aside 1: Bad

${3}" > "${T}/bad.md"
  zsh "${ASIDES}" --split --file "${T}/bad.md" --body-out "${T}/bad.body.md" --force >/dev/null 2>"${T}/err"; rc=$?
  check "${1} fails the split" 1 "${rc}"
  contains "${1} names the aside and why" "${2}" "$(cat "${T}/err")"
}
split_fails "an unlinked image" "n='1' kind='image'" "![Architecture](${SHORT_INK})"
split_fails "an image inside a sentence" "n='1' kind='image'" "See [![Architecture](${SHORT_INK})](${LINK_1}) here."
split_fails "an image linked to the editor" "does not link to its mermaid.live view | n='1'" "[![Architecture](${SHORT_INK})](https://mermaid.live/edit#pako:x)"
split_fails "an image from another host" "is not a mermaid.ink render | n='1'" "[![Architecture](https://example.com/a.png?width=620)](${LINK_1})"
split_fails "a mermaid.ink SVG" "is not a mermaid.ink render | n='1'" "[![Architecture](https://mermaid.ink/svg/base64:eyJ4IjoxfQ?width=620)](${LINK_1})"
split_fails "a WebP render" "type is not one Docs inserts | n='1' type='webp'" "[![Architecture](https://mermaid.ink/img/base64:eyJ4IjoxfQ?type=webp&width=620)](${LINK_1})"
split_fails "an image with no width" "needs a width inside the page | n='1' width=''" "[![Architecture](https://mermaid.ink/img/base64:eyJ4IjoxfQ)](${LINK_1})"
split_fails "an image wider than the page" "needs a width inside the page | n='1' width='800'" "[![Architecture](https://mermaid.ink/img/base64:eyJ4IjoxfQ?width=800)](${LINK_1})"
split_fails "a long URL that is not mermaid.ink base64" "is not a mermaid.ink render | n='1'" "[![Architecture](https://example.com/$(repeat 2100 print -rn -- x).png?width=620)](${LINK_1})"
split_fails "a long base64 URL with a percent escape" "is not a mermaid.ink base64 diagram | n='1'" "[![Architecture](https://mermaid.ink/img/base64:${LONG_PAYLOAD:0:100}%2B${LONG_PAYLOAD:100}?width=620)](${LINK_1})"
split_fails "a long base64 URL of bare mermaid source" "is not a mermaid.ink base64 diagram | n='1'" "[![Architecture](https://mermaid.ink/img/base64:$(print -rn -- "flowchart LR $(repeat 400 print -rn -- 'a-->b ')" | to_base64url)?width=620)](${LINK_1})"
split_fails "a mermaid fence" "mermaid fence in aside would publish as source text | n='1'" $'```mermaid\nflowchart LR\n```'
split_fails "an empty fence" "empty code fence in aside | n='1'" $'```\n```'

# --- the fill batch (dry run) ---

jq -n '{revisionId: "rev1", tabs: [{tabProperties: {tabId: "t.0", title: "Tab 1"}, documentTab: {body: {content: [
  {startIndex: 1, endIndex: 7, paragraph: {paragraphStyle: {namedStyleType: "HEADING_1", headingId: "h.intro"},
    elements: [{startIndex: 1, endIndex: 7, textRun: {content: "Intro\n", textStyle: {}}}]}},
  {startIndex: 7, endIndex: 40, paragraph: {paragraphStyle: {}, elements: [
    {startIndex: 7, endIndex: 11, textRun: {content: "See ", textStyle: {}}},
    {startIndex: 11, endIndex: 21, textRun: {content: "aside 1 ℹ️", textStyle: {link: {url: "#aside-1"}}}},
    {startIndex: 21, endIndex: 26, textRun: {content: " and ", textStyle: {}}},
    {startIndex: 26, endIndex: 36, textRun: {content: "aside 2 ℹ️", textStyle: {link: {url: "#aside-2"}}}},
    {startIndex: 36, endIndex: 38, textRun: {content: ".\n", textStyle: {}}}]}}]}}}]}' > "${T}/base_doc.json"

new_fake() {   # <dir>: a fake gws serving the base doc to every get, and every Drive target as readable
  mkdir -p "${1}"
  cp "${T}/base_doc.json" "${1}/docs-get.json"
  print -r -- '{"id": "readable"}' > "${1}/drive-get.json"
  print -r -- '{"replies": [{"addDocumentTab": {"tabProperties": {"tabId": "t.aside1"}}}, {"addDocumentTab": {"tabProperties": {"tabId": "t.aside2"}}}]}' > "${1}/docs-batchUpdate.1.json"
  print -r -- '{"replies": []}' > "${1}/docs-batchUpdate.2.json"
}

new_fake "${T}/dry"
FAKE_GWS_DIR="${T}/dry" PATH="${T}/bin:${PATH}" zsh "${ASIDES}" --rebuild --file "${T}/draft.md" --doc doc123 > "${T}/dry.out" 2>"${T}/err"; rc=$?
check "a rebuild without --execute exits 0" 0 "${rc}"
check "and sends no batch" false "$( [[ -f "${T}/dry/count.docs-batchUpdate" ]] && print true || print false )"
contains "the long URL is re-encoded as pako" "aside image URL re-encoded as pako | n='1'" "$(cat "${T}/err")"
jq -c 'select(any(.requests[]; .insertText))' "${T}/dry.out" > "${T}/fill.json"

tab_requests() {   # <tab id>: that tab's requests, in batch order
  jq -c --arg tab "${1}" '[.requests[] | select(([.. | objects | .tabId? // empty] | first) == $tab)]' "${T}/fill.json"
}
image_of() {   # <tab id>: its first image as {index, uri, at: position in the tab's requests}
  tab_requests "${1}" | jq -c 'to_entries | map(select(.value.insertInlineImage)) | first | {index: .value.insertInlineImage.location.index, uri: .value.insertInlineImage.uri, at: .key}'
}
tab_text() {   # <tab id>
  jq -r --arg tab "${1}" '.requests[] | select(.insertText.location.tabId == $tab) | .insertText.text' "${T}/fill.json"
}

image_1="$(image_of NEW_TAB_1)"
uri_1="$(jq -r '.uri' <<< "${image_1}")"
check "aside 1 gets one image" 1 "$(tab_requests NEW_TAB_1 | jq '[.[] | select(.insertInlineImage)] | length')"
contains "aside 1's image URI is mermaid.ink pako" "${PAKO_PREFIX}" "${uri_1}"
check "aside 1's image URI keeps the width" "?width=620" "${uri_1: -10}"
check "aside 1's image URI fits the 2 kB limit" true "$( (( ${#uri_1} <= 2048 )) && print true || print false )"
check "the base64 URL it replaced did not" true "$( (( ${#LONG_INK} > 2048 )) && print true || print false )"
payload="${uri_1#${PAKO_PREFIX}}"
payload="${payload%%\?*}"
check "the pako payload inflates to the diagram the base64 URL held" "${LONG_STATE}" \
  "$(node -e "process.stdout.write(require('zlib').inflateSync(Buffer.from(process.argv[1], 'base64url')).toString())" "${payload}")"
check "aside 2's two images keep their short URIs and links, in order" \
  "[{\"uri\":\"${SHORT_INK}\",\"link\":\"${LINK_2}\"},{\"uri\":\"${SHORT_INK}\",\"link\":\"${LINK_3}\"}]" \
  "$(tab_requests NEW_TAB_2 | jq -c 'to_entries | map(select(.value.insertInlineImage) | .key) as $at | [$at[] as $i | {uri: .[$i].value.insertInlineImage.uri, link: .[$i + 1].value.updateTextStyle.textStyle.link.url}] | reverse')"

index_1="$(jq '.index // 0' <<< "${image_1}")"
check "the image goes into an empty paragraph after a block separator" '"\n\n"' \
  "$(tab_text NEW_TAB_1 | jq -Rs --argjson i "${index_1}" '.[($i - 2):$i]')"
check "the image's link follows its insert, on the image alone" \
  "{\"startIndex\":${index_1},\"endIndex\":$(( index_1 + 1 )),\"url\":\"${LINK_1}\",\"fields\":\"link\"}" \
  "$(tab_requests NEW_TAB_1 | jq -c --argjson at "$(jq '.at // 0' <<< "${image_1}")" '.[$at + 1].updateTextStyle | {startIndex: .range.startIndex, endIndex: .range.endIndex, url: .textStyle.link.url, fields}')"
check "one chip per Drive link, a code span in its text included" 2 "$(tab_requests NEW_TAB_1 | jq '[.[] | select(.insertRichLink)] | length')"
check "chips and the image are placed highest index first" true \
  "$(tab_requests NEW_TAB_1 | jq '[.[] | (.deleteContentRange.range.startIndex // .insertInlineImage.location.index // empty)] | . == (sort | reverse) and length == 3 and (unique | length) == 3')"
check "no style follows the first chip or image" 0 \
  "$(tab_requests NEW_TAB_1 | jq 'to_entries | (map(select(.value.deleteContentRange or .value.insertInlineImage) | .key) | min) as $first | [.[$first:][] | .value | select(.updateParagraphStyle or (.updateTextStyle and (.updateTextStyle.textStyle.link.url // "" | startswith("https://mermaid.live/view#") | not)))] | length')"

span_style() {   # <tab id> <span text>: the font style request whose range covers exactly that text
  local text
  text="$(tab_text "${1}")"
  tab_requests "${1}" | jq -c --arg text "${text}" --arg span "${2}" \
    '[.[] | select(.updateTextStyle.textStyle.weightedFontFamily) | .updateTextStyle | select($text[(.range.startIndex - 1):(.range.endIndex - 1)] == $span) | {font: .textStyle.weightedFontFamily.fontFamily, color: .textStyle.foregroundColor.color.rgbColor, fields}] | first'
}
check "a code span is Roboto Mono in #188038" \
  '{"font":"Roboto Mono","color":{"red":0.09411765,"green":0.5019608,"blue":0.21960784},"fields":"weightedFontFamily,foregroundColor"}' \
  "$(span_style NEW_TAB_1 kubectl)"
check "a code span holding ![ is text, not an image" \
  '{"font":"Roboto Mono","color":{"red":0.09411765,"green":0.5019608,"blue":0.21960784},"fields":"weightedFontFamily,foregroundColor"}' \
  "$(span_style NEW_TAB_1 '![alt](src)')"
check "a code span inside a link keeps the link colour" '{"font":"Roboto Mono","color":null,"fields":"weightedFontFamily"}' "$(span_style NEW_TAB_1 gws)"
check "a fenced block stays Roboto Mono with no colour" '{"font":"Roboto Mono","color":null,"fields":"weightedFontFamily"}' "$(span_style NEW_TAB_2 'make build')"
check "a fenced block is shaded #F1F3F4" '[{"red":0.945098,"green":0.952941,"blue":0.956863}]' \
  "$(tab_requests NEW_TAB_2 | jq -c '[.[] | .updateParagraphStyle.paragraphStyle.shading.backgroundColor.color.rgbColor // empty]')"

# --- a marker the rebuild cannot find ---

new_fake "${T}/nomarker"
jq '.tabs[0].documentTab.body.content[1].paragraph.elements[3].textRun.textStyle = {}' "${T}/base_doc.json" > "${T}/nomarker/docs-get.json"
FAKE_GWS_DIR="${T}/nomarker" PATH="${T}/bin:${PATH}" zsh "${ASIDES}" --rebuild --execute --file "${T}/draft.md" --doc doc123 >/dev/null 2>"${T}/err"; rc=$?
check "a marker missing from the first tab fails the rebuild" 1 "${rc}"
contains "it names the marker" "marker not found in first tab | n='2'" "$(cat "${T}/err")"
check "and nothing was sent, so no tab was deleted or added" false "$( [[ -f "${T}/nomarker/count.docs-batchUpdate" ]] && print true || print false )"

# --- the verify read ---

final_doc() {   # <dir> <width_pt of aside 1's image> <aside 1's image links, JSON> <aside 2's image links, JSON>
  jq --argjson width "${2}" --argjson links_1 "${3}" --argjson links_2 "${4}" '
    def style: {pageSize: {width: {magnitude: 612, unit: "PT"}, height: {magnitude: 792, unit: "PT"}},
                marginLeft: {magnitude: 72}, marginRight: {magnitude: 72}, marginTop: {magnitude: 72}, marginBottom: {magnitude: 72}};
    def image_tab($id; $title; $w; $links; $chips):
      {tabProperties: {tabId: $id, title: $title}, documentTab: {documentStyle: style,
        inlineObjects: ([range($links | length) | {key: "kix.\($id).\(.)", value: {inlineObjectProperties: {embeddedObject: {size: {width: {magnitude: $w, unit: "PT"}, height: {magnitude: 300, unit: "PT"}}}}}}] | from_entries),
        body: {content: [{startIndex: 1, endIndex: 9, paragraph: {paragraphStyle: {}, elements: (
          [range($chips) | {richLink: {richLinkId: "kix.rl\(.)"}}]
          + [$links | to_entries[] | {inlineObjectElement: ({inlineObjectId: "kix.\($id).\(.key)"} + (if .value == "" then {} else {textStyle: {link: {url: .value}}} end))}]
          + [{textRun: {content: "\n", textStyle: {}}}])}}]}}};
    .tabs += [image_tab("t.aside1"; "Aside 1: Architecture"; $width; $links_1; 2),
              image_tab("t.aside2"; "Aside 2: Build"; 465; $links_2; 0)]' "${T}/base_doc.json" > "${1}/docs-get.3.json"
}
rebuild() {   # <dir>: stdout on $out, exit code on $rc, stderr in <dir>/err
  out="$(FAKE_GWS_DIR="${1}" PATH="${T}/bin:${PATH}" zsh "${ASIDES}" --rebuild --execute --file "${T}/draft.md" --doc doc123 2>"${1}/err")"; rc=$?
}
readonly LINKS_1="[\"${LINK_1}\"]"
readonly LINKS_2="[\"${LINK_2}\", \"${LINK_3}\"]"

new_fake "${T}/good"; final_doc "${T}/good" 465 "${LINKS_1}" "${LINKS_2}"
rebuild "${T}/good"
check "a rebuild whose images fit and link exits 0" 0 "${rc}"
check "its summary counts the images and chips per aside" '[{"images":1,"chips":2},{"images":2,"chips":0}]' "$(jq -c '[.asides[] | {images, chips}]' <<< "${out}")"
check "the fill batch went to the doc with all three images" 3 "$(jq '[.requests[] | select(.insertInlineImage)] | length' "${T}/good/batch.2.json")"

new_fake "${T}/wide"; final_doc "${T}/wide" 620 "${LINKS_1}" "${LINKS_2}"
rebuild "${T}/wide"
check "an aside image wider than the page fails the rebuild" 1 "${rc}"
contains "it names the aside and the page width" "aside tab image exceeds one page | n='1' tab='t.aside1' image='kix.t.aside1.0' width_pt='620' height_pt='300' max_width_pt='468'" "$(cat "${T}/wide/err")"

new_fake "${T}/unlinked"; final_doc "${T}/unlinked" 465 '[""]' "${LINKS_2}"
rebuild "${T}/unlinked"
check "an aside image without its view link fails the rebuild" 1 "${rc}"
contains "it names the aside and the expected link" "aside tab image does not link to its mermaid.live view | n='1'" "$(cat "${T}/unlinked/err")"

new_fake "${T}/swapped"; final_doc "${T}/swapped" 465 "${LINKS_1}" "[\"${LINK_3}\", \"${LINK_2}\"]"
rebuild "${T}/swapped"
check "two aside images with swapped links fail the rebuild" 1 "${rc}"
contains "it names the aside and the link it expected" "aside tab image does not link to its mermaid.live view | n='2' tab='t.aside2' image='kix.t.aside2.0' url='${LINK_3}' expected='${LINK_2}'" "$(cat "${T}/swapped/err")"

new_fake "${T}/missing"; final_doc "${T}/missing" 465 '[]' "${LINKS_2}"
rebuild "${T}/missing"
check "an aside tab missing its image fails the rebuild" 1 "${rc}"
contains "it names the counts" "aside tab images missing | n='1' tab='t.aside1' images='0' expected='1'" "$(cat "${T}/missing/err")"

print -r -- "pass=${pass} fail=${fail}"
(( fail == 0 ))
