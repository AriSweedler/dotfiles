#!/usr/bin/env zsh
# The dry-run default of every script here that writes a Doc, against a fake gws on PATH; no network, no
# real Doc. It checks:
#   - gdoc_publish.zsh, gdoc_finish.zsh and gdoc_asides.zsh --rebuild with no flag send no write
#   - --dry-run, --dry-run with --execute in either order, and an inherited DRY_RUN=1 with --execute
#     send no write; an inherited DRY_RUN=0 alone sends none either
#   - gdoc_publish.zsh --execute uploads, then its finish, asides and bookmark children write: the
#     parent hands each --execute, since none writes without it. A dry run only checks the bookmark
#     setup; a crashed check, a failed apply, or an apply that dry-ran fails the publish
# HOME is a throwaway with only the skills these scripts source; the bookmark step is a fake, installed
# for its own cases only.
# Run: zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/tests/gdoc_dry_run.test.zsh

set -uo pipefail
unset DRY_RUN

readonly SKILL_DIR="${0:A:h:h}"
readonly REAL_SKILLS="${HOME}/.claude/skills"

missing=()
for cmd in jq python3; do
  command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
done
if (( ${#missing} > 0 )); then
  print -ru2 -- "[ERROR] missing required commands | missing='${(j:, :)missing}'"
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
mkdir -p "${T}/bin" "${T}/home/.claude/skills"
for skill in ari-hemingway--share-gdoc ari-hemingway--lib ari-skill-shellscripts ari-skill-pythonscripts; do
  ln -s "${REAL_SKILLS}/${skill}" "${T}/home/.claude/skills/${skill}"
done
readonly PUBLISH="${T}/home/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh"
readonly FINISH="${T}/home/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh"
readonly ASIDES="${T}/home/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.zsh"

# The fake gws: every call's argv as one JSON line in calls.jsonl, and the reply from
# `<a>-<b>-<c>.<n>.json` when present, else `<a>-<b>-<c>.json`, else `{}`.
cat > "${T}/bin/gws" <<'FAKE'
#!/usr/bin/env zsh
set -euo pipefail
jq -cn '$ARGS.positional' --args -- "${@}" >> "${FAKE_GWS_DIR}/calls.jsonl"
kind="${1:-}-${2:-}-${3:-}"
counter="${FAKE_GWS_DIR}/count.${kind}"
typeset -i n=$(( $(cat "${counter}" 2>/dev/null || print 0) + 1 ))
print -r -- "${n}" > "${counter}"
reply="${FAKE_GWS_DIR}/${kind}.${n}.json"
[[ -f "${reply}" ]] || reply="${FAKE_GWS_DIR}/${kind}.json"
if [[ -f "${reply}" ]]; then cat "${reply}"; else print -r -- '{}'; fi
FAKE
chmod +x "${T}/bin/gws"

readonly DRIVE_LINK="https://docs.google.com/document/d/DOC_B/edit"
print -r -- "[🤖 AI generated] Dry run test

# Intro

See ${DRIVE_LINK} and the note ([aside 1 ℹ️](#aside-1)).

# Useful links

# Aside 1: Note

Plain text." > "${T}/draft.md"

# finish's reads: a plain Drive link, then the chip the batch made of it. asides' reads: the first
# tab with the marker, the revision after the tabs batch, and the aside tab it filled.
style='{pageSize: {width: {magnitude: 612}, height: {magnitude: 792}}, marginLeft: {magnitude: 72}, marginRight: {magnitude: 72}, marginTop: {magnitude: 72}, marginBottom: {magnitude: 72}}'
new_fake() {   # <dir>
  mkdir -p "${1}"
  print -r -- '{"scopes": ["https://www.googleapis.com/auth/documents", "https://www.googleapis.com/auth/drive"]}' > "${1}/auth-status-.json"
  print -r -- '{"id": "DOC_A", "parents": ["FOLDER"]}' > "${1}/drive-files-update.json"
  print -r -- '{"id": "DOC_A", "name": "Live doc", "mimeType": "application/vnd.google-apps.document", "modifiedTime": "2026-11-05T09:00:00Z", "lastModifyingUser": {"displayName": "Someone Else"}, "capabilities": {"canEdit": true}}' > "${1}/drive-files-get.json"
  print -r -- '{"id": "DOC_NEW", "parents": ["FOLDER"]}' > "${1}/drive-files-create.json"
  jq -n --arg url "${DRIVE_LINK}" "{revisionId: \"rev1\", documentStyle: ${style}, body: {content: [
    {startIndex: 1, endIndex: 30, paragraph: {elements: [{startIndex: 1, endIndex: 30, textRun: {content: \"see\", textStyle: {link: {url: \$url}}}}]}}]}}" > "${1}/docs-documents-get.1.json"
  jq -n "{revisionId: \"rev2\", documentStyle: ${style}, body: {content: [
    {startIndex: 1, endIndex: 3, paragraph: {elements: [{startIndex: 1, endIndex: 2, richLink: {richLinkId: \"kix.rl\"}}]}}]}}" > "${1}/docs-documents-get.2.json"
  jq -n '{revisionId: "rev3", tabs: [{tabProperties: {tabId: "t.0", title: "Tab 1"}, documentTab: {body: {content: [
    {startIndex: 1, endIndex: 7, paragraph: {paragraphStyle: {namedStyleType: "HEADING_1", headingId: "h.intro"},
      elements: [{startIndex: 1, endIndex: 7, textRun: {content: "Intro\n", textStyle: {}}}]}},
    {startIndex: 7, endIndex: 20, paragraph: {paragraphStyle: {}, elements: [
      {startIndex: 7, endIndex: 17, textRun: {content: "aside 1 ℹ️", textStyle: {link: {url: "#aside-1"}}}},
      {startIndex: 17, endIndex: 19, textRun: {content: ".\n", textStyle: {}}}]}}]}}}]}' > "${1}/docs-documents-get.3.json"
  jq '.revisionId = "rev4"' "${1}/docs-documents-get.3.json" > "${1}/docs-documents-get.4.json"
  jq "(.tabs += [{tabProperties: {tabId: \"t.aside1\", title: \"Aside 1: Note\"}, documentTab: {documentStyle: ${style}, body: {content: [
    {startIndex: 1, endIndex: 3, paragraph: {paragraphStyle: {}, elements: [{startIndex: 1, endIndex: 3, textRun: {content: \"x\n\", textStyle: {}}}]}}]}}}]) | .revisionId = \"rev5\"" \
    "${1}/docs-documents-get.3.json" > "${1}/docs-documents-get.5.json"
  print -r -- '{"replies": [{"addDocumentTab": {"tabProperties": {"tabId": "t.aside1"}}}]}' > "${1}/docs-documents-batchUpdate.2.json"
}

run() {   # <dir> <env: KEY=VALUE or -> <script> <args…>: stdout on $out, exit code on $rc, stderr in <dir>/err
  local dir="${1}" env_kv="${2}" script="${3}"
  shift 3
  new_fake "${dir}"
  local -a env_args
  env_args=(HOME="${T}/home" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}")
  [[ "${env_kv}" != "-" ]] && env_args+=("${env_kv}")
  out="$(env "${env_args[@]}" zsh "${script}" "${@}" 2>"${dir}/err")"; rc=$?
}
writes() {   # <dir>: the gws calls that write, one per line (an upload or a batchUpdate without gws --dry-run)
  [[ -f "${1}/calls.jsonl" ]] || return 0
  jq -r 'select((.[0:3] == ["drive", "files", "update"] or .[0:3] == ["drive", "files", "create"] or .[0:3] == ["docs", "documents", "batchUpdate"]) and (index("--dry-run") | not)) | .[0:3] | join(" ")' "${1}/calls.jsonl"
}
calls_of() {   # <dir> <a b c>: how many calls of that kind, writes or not
  [[ -f "${1}/calls.jsonl" ]] || { print 0; return 0; }
  jq -s --arg kind "${2}" '[.[] | select(.[0:3] | join(" ") == $kind)] | length' "${1}/calls.jsonl"
}

# --- gdoc_publish.zsh: every way to ask for a dry run writes nothing ---

publish_is_dry() {   # <name> <env or -> <args…>
  local name="${1}" env_kv="${2}"
  shift 2
  run "${T}/${name// /_}" "${env_kv}" "${PUBLISH}" --file "${T}/draft.md" --doc DOC_A "${@}"
  check "publish, ${name}: exits 0" 0 "${rc}"
  check "publish, ${name}: writes nothing" "" "$(writes "${T}/${name// /_}")"
  check "publish, ${name}: prints no URL" "" "${out}"
  contains "publish, ${name}: says it wrote nothing" "Dry run valid; nothing written | would='update'" "$(cat "${T}/${name// /_}/err")"
}
publish_is_dry "no flag" -
publish_is_dry "--dry-run" - --dry-run
publish_is_dry "--execute --dry-run" - --execute --dry-run
publish_is_dry "--dry-run --execute" - --dry-run --execute
publish_is_dry "inherited DRY_RUN=1 with --execute" DRY_RUN=1 --execute
publish_is_dry "inherited DRY_RUN=0 alone" DRY_RUN=0
contains "publish with no flag says the dry run is the default" "Dry run: the default; nothing will change" "$(cat "${T}/no_flag/err")"
check "publish with no flag still validates the upload with Drive" 1 "$(calls_of "${T}/no_flag" "drive files update")"
contains "publish with no flag leaves --execute to the user's reply" "next='show the user what would be written; --execute only after they reply'" "$(cat "${T}/no_flag/err")"
contains "an update's dry run names the Doc it would replace" "Doc to replace; its whole body and every tab but the first go | doc='DOC_A' name='Live doc' modified='2026-11-05T09:00:00Z' modified_by='Someone Else'" "$(cat "${T}/no_flag/err")"

# --- gdoc_publish.zsh: a target that is not an editable Doc fails before any upload ---

new_fake "${T}/not_a_doc"
print -r -- '{"id": "F", "mimeType": "application/vnd.google-apps.folder", "capabilities": {"canEdit": true}}' > "${T}/not_a_doc/drive-files-get.json"
out="$(env HOME="${T}/home" FAKE_GWS_DIR="${T}/not_a_doc" PATH="${T}/bin:${PATH}" zsh "${PUBLISH}" --file "${T}/draft.md" --doc F --execute 2>"${T}/not_a_doc/err")"; rc=$?
check "publish --execute to a non-Doc id exits 1" 1 "${rc}"
check "and uploads nothing, not even a dry run" 0 "$(calls_of "${T}/not_a_doc" "drive files update")"
contains "and names the mime type" "Target is not a Google Doc | doc='F' mime_type='application/vnd.google-apps.folder'" "$(cat "${T}/not_a_doc/err")"
run "${T}/doc_url" - "${PUBLISH}" --file "${T}/draft.md" --doc "https://docs.google.com/document/d/DOC_A?tab=t.0#heading=h.x"
contains "a Doc URL with ?tab= and # reduces to the id" "Doc to replace; its whole body and every tab but the first go | doc='DOC_A'" "$(cat "${T}/doc_url/err")"

# --- gdoc_publish.zsh: a create ---

create_fake() {   # <dir>: the first files.get is the folder lookup
  new_fake "${1}"
  print -r -- '{"id": "FOLDER", "name": "Drafts", "mimeType": "application/vnd.google-apps.folder", "capabilities": {"canAddChildren": true}}' > "${1}/drive-files-get.1.json"
}
create_fake "${T}/create_dry"
out="$(env HOME="${T}/home" FAKE_GWS_DIR="${T}/create_dry" PATH="${T}/bin:${PATH}" zsh "${PUBLISH}" --file "${T}/draft.md" --folder FOLDER 2>"${T}/create_dry/err")"; rc=$?
check "a create with no flag exits 0" 0 "${rc}"
check "and writes nothing" "" "$(writes "${T}/create_dry")"
contains "and says what it would create, where" "would='create' title='[🤖 AI generated] Dry run test' doc='' folder='FOLDER' folder_name='Drafts'" "$(cat "${T}/create_dry/err")"
create_fake "${T}/create_execute"
out="$(env HOME="${T}/home" FAKE_GWS_DIR="${T}/create_execute" PATH="${T}/bin:${PATH}" zsh "${PUBLISH}" --file "${T}/draft.md" --folder FOLDER --execute 2>"${T}/create_execute/err")"; rc=$?
check "a create with --execute exits 0 and prints the new Doc's URL" "0 https://docs.google.com/document/d/DOC_NEW/edit" "${rc} ${out}"
check "it creates exactly one Doc, inside the folder" '["FOLDER"]' \
  "$(jq -cs '[.[] | select(.[0:3] == ["drive", "files", "create"]) | .[index("--json") + 1] | fromjson | .parents] | if length == 1 then .[0] else . end' "${T}/create_execute/calls.jsonl")"
print -r -- "[🤖 AI generated] Title only" > "${T}/empty.md"
run "${T}/empty" - "${PUBLISH}" --file "${T}/empty.md" --doc DOC_A --execute
check "a draft with a title and no body exits 1 before any Drive call" "1 0" "${rc} $(calls_of "${T}/empty" "drive files update")"

# --- gdoc_publish.zsh --execute: it uploads, and its children write ---

run "${T}/execute" - "${PUBLISH}" --file "${T}/draft.md" --doc DOC_A --execute
check "publish --execute exits 0" 0 "${rc}"
check "publish --execute prints the URL" "https://docs.google.com/document/d/DOC_A/edit" "${out}"
check "publish --execute uploads, then finish and the asides rebuild write their batches" \
  $'drive files update\ndocs documents batchUpdate\ndocs documents batchUpdate\ndocs documents batchUpdate' "$(writes "${T}/execute")"
check "the finish batch chips the Drive link" "deleteContentRange,insertRichLink" \
  "$(jq -rs '[.[] | select(.[0:3] == ["docs", "documents", "batchUpdate"])] | first | .[index("--json") + 1] | fromjson | [.requests[] | keys[0]] | join(",")' "${T}/execute/calls.jsonl")"
contains "with no bookmark skill the step warns and the publish still passes" "Bookmarks skipped; the bookmark skill is not installed" "$(cat "${T}/execute/err")"

# --- the bookmark step: gdoc_bookmarks.zsh writes only with --execute, so publish hands it on ---

readonly FAKE_BOOKMARK_SKILL="${T}/home/.claude/skills/ari-hemingway--structure-bookmark"
mkdir -p "${FAKE_BOOKMARK_SKILL}/bin"
# The fake bookmark step: every call's argv but --help as one line in bookmarks.calls; FAKE_BOOKMARKS_MODE
# picks ok (the default), missing (a MISSING setup), crash (exit 1, no MISSING line), old (no --execute
# in its help), apply_fail, or dry_reply (exits 0 but reports a dry run).
cat > "${FAKE_BOOKMARK_SKILL}/bin/gdoc_bookmarks.zsh" <<'FAKE'
#!/usr/bin/env zsh
mode="${FAKE_BOOKMARKS_MODE:-ok}"
if [[ "${1}" == "--help" ]]; then
  [[ "${mode}" == old ]] && { print -r -- "usage: gdoc_bookmarks.py [--dry-run]"; exit 0; }
  print -r -- "  --execute  write"
  exit 0
fi
print -r -- "${*}" >> "${FAKE_GWS_DIR}/bookmarks.calls"
if [[ "${1}" == "--check-setup" ]]; then
  [[ "${mode}" == missing ]] && { print -r -- "MISSING  project: run: gws script projects create"; exit 1; }
  [[ "${mode}" == crash ]] && { print -ru2 -- "ModuleNotFoundError: No module named 'skill_log'"; exit 1; }
  print -r -- "OK       scopes"
  exit 0
fi
[[ "${mode}" == apply_fail ]] && exit 1
[[ "${mode}" == dry_reply ]] && { print -r -- '{"dry_run": 1}'; exit 0; }
print -r -- '{"dry_run": 0}'
FAKE
bookmark_run() {   # <dir> <mode> <args…>: the publish under that fake mode
  local dir="${1}" mode="${2}"
  shift 2
  new_fake "${dir}"
  out="$(env HOME="${T}/home" FAKE_GWS_DIR="${dir}" FAKE_BOOKMARKS_MODE="${mode}" PATH="${T}/bin:${PATH}" zsh "${PUBLISH}" "${@}" 2>"${dir}/err")"; rc=$?
}
bookmark_calls() {   # <dir>: the fake's calls, with the staged draft path elided
  [[ -f "${1}/bookmarks.calls" ]] || return 0
  awk '{ sub(/--file [^ ]+/, "--file DRAFT"); print }' "${1}/bookmarks.calls"
}

bookmark_run "${T}/bm_execute" ok --file "${T}/draft.md" --doc DOC_A --execute
check "publish --execute with the bookmark skill exits 0" 0 "${rc}"
check "it checks the setup, then applies with --execute" $'--check-setup\n--apply --execute --doc DOC_A --file DRAFT' "$(bookmark_calls "${T}/bm_execute")"
bookmark_run "${T}/bm_dry" ok --file "${T}/draft.md" --doc DOC_A
check "a dry-run publish only checks the setup, never applies" "--check-setup" "$(bookmark_calls "${T}/bm_dry")"
contains "and says the bookmarks would be applied" "bookmarks='would-apply'" "$(cat "${T}/bm_dry/err")"
bookmark_run "${T}/bm_missing_dry" missing --file "${T}/draft.md" --doc DOC_A
contains "a dry run with the setup missing says they would be skipped" "bookmarks='skipped'" "$(cat "${T}/bm_missing_dry/err")"
contains "and leaves the setup command to the user" "next='offer the one-time setup in /ari-hemingway--structure-bookmark; run nothing from missing= unasked'" "$(cat "${T}/bm_missing_dry/err")"
bookmark_run "${T}/bm_missing" missing --file "${T}/draft.md" --doc DOC_A --execute
check "a missing setup skips the apply and the publish still exits 0" "0 --check-setup" "${rc} $(bookmark_calls "${T}/bm_missing")"
bookmark_run "${T}/bm_crash" crash --file "${T}/draft.md" --doc DOC_A --execute
check "a setup check that crashes fails the publish, and nothing is applied" "1 --check-setup" "${rc} $(bookmark_calls "${T}/bm_crash")"
contains "and names the crash" "Bookmark setup check failed | exit_code='1' error='ModuleNotFoundError: No module named 'skill_log''" "$(cat "${T}/bm_crash/err")"
bookmark_run "${T}/bm_old" old --file "${T}/draft.md" --doc DOC_A --execute
check "a bookmark skill without --execute is skipped before any call, and the publish exits 0" "0 " "${rc} $(bookmark_calls "${T}/bm_old")"
contains "and says to update it" "the bookmark skill predates --execute" "$(cat "${T}/bm_old/err")"
bookmark_run "${T}/bm_fail" apply_fail --file "${T}/draft.md" --doc DOC_A --execute
check "a failed apply fails the publish, which still prints the URL" "1 https://docs.google.com/document/d/DOC_A/edit" "${rc} ${out}"
bookmark_run "${T}/bm_dry_reply" dry_reply --file "${T}/draft.md" --doc DOC_A --execute
check "an apply that reports a dry run fails the publish" 1 "${rc}"
contains "and says the step did not execute" "Bookmark step did not execute" "$(cat "${T}/bm_dry_reply/err")"
print -r -- "[🤖 AI generated] Plain

# Intro

Nothing to bookmark." > "${T}/plain.md"
bookmark_run "${T}/bm_none" ok --file "${T}/plain.md" --doc DOC_A --execute
check "a draft with no asides and no #bm- or #goto- link never calls the bookmark step" "0 " "${rc} $(bookmark_calls "${T}/bm_none")"
new_fake "${T}/bm_finish_fail"
print -r -- '{"error": "refused"}' > "${T}/bm_finish_fail/docs-documents-batchUpdate.1.json"
jq '.body.content[0].paragraph.elements[0].textRun.textStyle.link.url = "https://docs.google.com/document/d/DOC_B/edit"' "${T}/bm_finish_fail/docs-documents-get.1.json" > "${T}/bm_finish_fail/docs-documents-get.2.json"
out="$(env HOME="${T}/home" FAKE_GWS_DIR="${T}/bm_finish_fail" FAKE_BOOKMARKS_MODE=ok PATH="${T}/bin:${PATH}" zsh "${PUBLISH}" --file "${T}/draft.md" --doc DOC_A --execute 2>"${T}/bm_finish_fail/err")"; rc=$?
check "after a failed finish the bookmark step is skipped and the publish fails" "1 " "${rc} $(bookmark_calls "${T}/bm_finish_fail")"
rm -rf "${FAKE_BOOKMARK_SKILL}"

# --- gdoc_finish.zsh and gdoc_asides.zsh --rebuild alone ---

run "${T}/finish_no_flag" - "${FINISH}" --doc DOC_A
check "finish with no flag exits 0" 0 "${rc}"
check "finish with no flag writes nothing" "" "$(writes "${T}/finish_no_flag")"
check "finish with no flag validates its batch with gws --dry-run" 1 "$(calls_of "${T}/finish_no_flag" "docs documents batchUpdate")"
run "${T}/finish_inherited" DRY_RUN=1 "${FINISH}" --doc DOC_A --execute
check "finish --execute under an inherited DRY_RUN=1 writes nothing" "" "$(writes "${T}/finish_inherited")"
run "${T}/finish_execute" - "${FINISH}" --doc DOC_A --execute
check "finish --execute exits 0" 0 "${rc}"
check "finish --execute sends its batch" "docs documents batchUpdate" "$(writes "${T}/finish_execute")"

# A Drive URL in a header cell: the chip shortens the cell, so every style on the read's ranges must
# run before it, or the header's bold and centering spill into the next cell.
new_fake "${T}/header_link"
jq -n --arg url "${DRIVE_LINK}" "{revisionId: \"rev1\", documentStyle: ${style}, body: {content: [
  {startIndex: 1, endIndex: 60, table: {rows: 1, columns: 2,
    tableStyle: {tableColumnProperties: [{width: {magnitude: 234}}, {width: {magnitude: 234}}]},
    tableRows: [{tableRowStyle: {tableHeader: true}, tableCells: [
      {content: [{startIndex: 3, endIndex: 50, paragraph: {elements: [{startIndex: 3, endIndex: 50, textRun: {content: (\$url + \"\n\"), textStyle: {link: {url: \$url}}}}]}}]},
      {content: [{startIndex: 51, endIndex: 56, paragraph: {elements: [{startIndex: 51, endIndex: 56, textRun: {content: \"note\n\", textStyle: {}}}]}}]}]}]}}]}}" > "${T}/header_link/docs-documents-get.json"
rm "${T}/header_link"/docs-documents-get.[0-9].json
env HOME="${T}/home" FAKE_GWS_DIR="${T}/header_link" PATH="${T}/bin:${PATH}" zsh "${FINISH}" --doc DOC_A >/dev/null 2>"${T}/header_link/err"
check "a header-cell Drive link's chip runs after every style in the batch" true \
  "$(jq -s '[.[] | select(.[0:3] == ["docs", "documents", "batchUpdate"])] | first | .[index("--json") + 1] | fromjson | .requests | to_entries
    | (map(select(.value.deleteContentRange or .value.insertRichLink) | .key) | min) as $first_chip
    | (map(select(.value.updateTextStyle or .value.updateParagraphStyle or .value.updateTableCellStyle) | .key) | max) as $last_style
    | $first_chip != null and $last_style != null and $last_style < $first_chip' "${T}/header_link/calls.jsonl")"

# asides reads the tabs form: point its first read at the tabs doc.
asides_run() {   # <dir> <env or -> <args…>
  local dir="${1}" env_kv="${2}"
  shift 2
  new_fake "${dir}"
  cp "${dir}/docs-documents-get.3.json" "${dir}/docs-documents-get.json"
  rm "${dir}"/docs-documents-get.[0-9].json
  local -a env_args
  env_args=(HOME="${T}/home" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}")
  [[ "${env_kv}" != "-" ]] && env_args+=("${env_kv}")
  out="$(env "${env_args[@]}" zsh "${ASIDES}" --rebuild --file "${T}/draft.md" --doc DOC_A "${@}" 2>"${dir}/err")"; rc=$?
}
asides_run "${T}/asides_no_flag" -
check "asides --rebuild with no flag exits 0" 0 "${rc}"
check "asides --rebuild with no flag calls no batchUpdate" 0 "$(calls_of "${T}/asides_no_flag" "docs documents batchUpdate")"
contains "asides --rebuild with no flag prints the batch it would send" '"addDocumentTab"' "${out}"
contains "and logs what it would rebuild" "would rebuild aside tab | n='1'" "$(cat "${T}/asides_no_flag/err")"
check "and logs no tab as rebuilt or deleted" "" "$(awk '/aside tab rebuilt|stale aside tab deleted/' "${T}/asides_no_flag/err")"
asides_run "${T}/asides_both" - --execute --dry-run
check "asides --rebuild --execute --dry-run calls no batchUpdate" 0 "$(calls_of "${T}/asides_both" "docs documents batchUpdate")"
asides_run "${T}/asides_inherited" DRY_RUN=1 --execute
check "asides --rebuild --execute under an inherited DRY_RUN=1 calls no batchUpdate" 0 "$(calls_of "${T}/asides_inherited" "docs documents batchUpdate")"
asides_run "${T}/asides_zero" DRY_RUN=0
check "asides --rebuild under an inherited DRY_RUN=0 alone calls no batchUpdate" 0 "$(calls_of "${T}/asides_zero" "docs documents batchUpdate")"

print -r -- "pass=${pass} fail=${fail}"
(( fail == 0 ))
