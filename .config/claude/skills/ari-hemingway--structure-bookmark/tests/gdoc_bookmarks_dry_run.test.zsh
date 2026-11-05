#!/usr/bin/env zsh
# The dry-run default of gdoc_bookmarks.zsh against a fake gws on PATH and a throwaway HOME; no network,
# no real Doc or Apps Script project, no real config. It checks:
#   - --apply with no flag, --dry-run, --dry-run with --execute in either order, an inherited DRY_RUN=1
#     with --execute, and an inherited DRY_RUN=0 alone run no addBookmarks and send no batch
#   - the --apply dry run still reads the Doc, prints the relink batch, logs the rerun with --execute,
#     and fails on a missing setup as the real run does
#   - a malformed link, a missing draft, a target the Doc lacks or holds twice, and a corrupt config
#     fail before any write, dry run or not; a re-apply finds a code-span target by its rendered text
#   - --apply --execute, alone or under a parent's DRY_RUN=0, runs addBookmarks and sends the batch
#   - --configure writes the config only under --execute, drops the old deployment with a new
#     project, and a repeat changes nothing
#   - --check-setup takes neither flag, and every --configure it prints carries --execute
# Run: zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/tests/gdoc_bookmarks_dry_run.test.zsh

set -uo pipefail
unset DRY_RUN

readonly SKILL_DIR="${0:A:h:h}"
readonly REAL_SKILLS="${HOME}/.claude/skills"
readonly REAL_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

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
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass += 1 )); print -r -- "ok      ${1}"
  else (( fail += 1 )); print -r -- "FAIL    ${1} | unwanted='${2}' haystack='${3:0:300}'"; fi
}

readonly T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/skills"
ln -s "${SKILL_DIR}" "${T}/skills/ari-hemingway--structure-bookmark"
for skill in ari-hemingway--lib ari-skill-shellscripts ari-skill-pythonscripts; do
  ln -s "${REAL_SKILLS}/${skill}" "${T}/skills/${skill}"
done

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

print -r -- "Dry run test

# Intro

Do not proceed until [the status reads done](#bm-status-done). That is the [gate](#goto-status-done)." > "${T}/draft.md"

# The Doc as imported (every read of a dry run, the first two of a real one), then as the relink leaves it.
new_case() {   # <name>: a fresh case dir holding the fake's replies and the throwaway HOME
  local dir="${T}/${1// /_}"
  mkdir -p "${dir}/home/.claude" "${dir}/home/.local/share/ari-hemingway"
  ln -s "${T}/skills" "${dir}/home/.claude/skills"
  print -r -- '{"scriptId": "SCRIPT_A", "deploymentId": "DEPLOY_A"}' > "${dir}/home/.local/share/ari-hemingway/gdoc_bookmarks.json"
  jq -n '{revisionId: "rev1", tabs: [{tabProperties: {tabId: "t.0", title: "Tab 1"}, documentTab: {body: {content: [
    {startIndex: 1, endIndex: 60, paragraph: {elements: [
      {startIndex: 1, endIndex: 22, textRun: {content: "the status reads done", textStyle: {link: {url: "#bm-status-done"}}}},
      {startIndex: 22, endIndex: 35, textRun: {content: ". That is the ", textStyle: {}}},
      {startIndex: 35, endIndex: 39, textRun: {content: "gate", textStyle: {link: {url: "#goto-status-done"}}}},
      {startIndex: 39, endIndex: 41, textRun: {content: ".\n", textStyle: {}}}]}}]}}}]}' > "${dir}/docs-documents-get.json"
  jq '.revisionId = "rev3" | .tabs[0].documentTab.body.content[0].paragraph.elements[0].textRun.textStyle = {}
    | .tabs[0].documentTab.body.content[0].paragraph.elements[2].textRun.textStyle = {link: {bookmark: {id: "id.abc", tabId: "t.0"}}}' \
    "${dir}/docs-documents-get.json" > "${dir}/docs-documents-get.3.json"
  print -r -- '{"response": {"result": {"bm-status-done": "id.abc"}}}' > "${dir}/script-scripts-run.json"
  print -r -- "${dir}"
}

run() {   # <name> <env: KEY=VALUE or -> <args…>: stdout on $out, exit code on $rc, the case dir on $dir
  local name="${1}" env_kv="${2}"
  shift 2
  dir="$(new_case "${name}")"
  local -a env_args
  env_args=(HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}")
  [[ "${env_kv}" != "-" ]] && env_args+=("${env_kv}")
  out="$(env "${env_args[@]}" zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" "${@}" 2>"${dir}/err")"; rc=$?
}
writes() {   # <dir>: the gws calls that write, one per line
  [[ -f "${1}/calls.jsonl" ]] || return 0
  jq -r 'select(.[0:3] == ["script", "scripts", "run"] or .[0:3] == ["docs", "documents", "batchUpdate"]) | .[0:3] | join(" ")' "${1}/calls.jsonl"
}
calls_of() {   # <dir> <a b c>
  [[ -f "${1}/calls.jsonl" ]] || { print 0; return 0; }
  jq -s --arg kind "${2}" '[.[] | select(.[0:3] | join(" ") == $kind)] | length' "${1}/calls.jsonl"
}
last_json() {   # <stdout>: the dry_run field of its last line
  print -r -- "${1}" | awk 'NF { last = $0 } END { print last }' | jq -r '.dry_run'
}

# --- --apply: every way to ask for a dry run writes nothing ---

apply_is_dry() {   # <name> <env or -> <args…>
  local name="${1}" env_kv="${2}"
  shift 2
  run "${name}" "${env_kv}" --apply --doc DOC_A --file "${T}/draft.md" "${@}"
  check "apply, ${name}: exits 0" 0 "${rc}"
  check "apply, ${name}: runs no addBookmarks and sends no batch" "" "$(writes "${dir}")"
  check "apply, ${name}: reports dry_run 1" 1 "$(last_json "${out}")"
}
apply_is_dry "no flag" -
apply_is_dry "--dry-run" - --dry-run
apply_is_dry "--execute --dry-run" - --execute --dry-run
apply_is_dry "--dry-run --execute" - --dry-run --execute
apply_is_dry "inherited DRY_RUN=1 with --execute" DRY_RUN=1 --execute
apply_is_dry "inherited DRY_RUN=0 alone" DRY_RUN=0

run "no flag detail" - --apply --doc DOC_A --file "${T}/draft.md"
contains "apply with no flag says the dry run is the default" "Dry run: the default; nothing will change" "$(cat "${dir}/err")"
check "apply with no flag still reads the Doc" 2 "$(calls_of "${dir}" "docs documents get")"
contains "apply with no flag prints the relink batch it would send" '"bookmark": {"id": "BOOKMARK_bm-status-done"' "${out}"
contains "apply with no flag logs what it would bookmark" "would bookmark target | key='bm-status-done'" "$(cat "${dir}/err")"
contains "apply with no flag logs the rerun with --execute" "rerun='zsh \$HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc DOC_A --file ${T}/draft.md --execute'" "$(cat "${dir}/err")"

dir="$(new_case "no setup")"
print -r -- '{"scriptId": "SCRIPT_A"}' > "${dir}/home/.local/share/ari-hemingway/gdoc_bookmarks.json"
out="$(env HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}" \
  zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" --apply --doc DOC_A --file "${T}/draft.md" 2>"${dir}/err")"; rc=$?
check "an apply dry run with no deployment recorded fails as the real run does" 1 "${rc}"
contains "and names the setup check" "bookmark setup incomplete" "$(cat "${dir}/err")"

# --- --apply: a draft or Doc the real run would fail on fails before any write, in either mode ---

fails_before_writes() {   # <name> <needle> <draft text or -> <args…>: the draft replaces draft.md when given
  local name="${1}" needle="${2}" text="${3}"
  shift 3
  local draft="${T}/draft.md"
  if [[ "${text}" != "-" ]]; then
    draft="${T}/${name// /_}.md"
    print -r -- "${text}" > "${draft}"
  fi
  run "${name}" - --apply --doc DOC_A --file "${draft}" "${@}"
  check "${name}: exits 1" 1 "${rc}"
  check "${name}: writes nothing" "" "$(writes "${dir}")"
  contains "${name}: names the problem" "${needle}" "$(cat "${dir}/err")"
}
fails_before_writes "an underscore slug" "malformed #bm-/#goto- link | link='](#bm-status_done)'" \
  "Do not proceed until [the status reads done](#bm-status_done)." --execute
fails_before_writes "a ] in the text" "malformed #bm-/#goto- link" "See [the [x] box](#bm-box)." --execute
fails_before_writes "a missing draft" "draft not found" - --file "${T}/nope.md" --execute
fails_before_writes "a target absent from the Doc" "target not found in the first tab | key='bm-elsewhere'" \
  "Read [some other sentence](#bm-elsewhere)." --execute
fails_before_writes "a dry run with a target absent from the Doc" "target not found in the first tab" \
  "Read [some other sentence](#bm-elsewhere)."
fails_before_writes "a target whose text occurs twice" "target text occurs more than once | key='bm-x' text='e'" \
  "One [e](#bm-x) and [gate](#goto-x)." --execute

dir="$(new_case "corrupt config")"
print -r -- '{not json' > "${dir}/home/.local/share/ari-hemingway/gdoc_bookmarks.json"
env HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}" \
  zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" --apply --doc DOC_A --file "${T}/draft.md" --execute >/dev/null 2>"${dir}/err"; rc=$?
check "a corrupt config exits 1 with no traceback" "1 0" "${rc} $(awk '/Traceback/ { n += 1 } END { print n + 0 }' "${dir}/err")"
contains "and names the file" "bookmark config is not JSON" "$(cat "${dir}/err")"

# A re-apply after the link style was stripped: the code span's backticks are not in the Doc's text.
print -r -- "Do not proceed until [\`the status reads done\`](#bm-status-done). That is the [gate](#goto-status-done)." > "${T}/code_span.md"
dir="$(new_case "code span re-apply")"
cp "${dir}/docs-documents-get.3.json" "${dir}/docs-documents-get.json"
out="$(env HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}" \
  zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" --apply --doc DOC_A --file "${T}/code_span.md" 2>"${dir}/err")"; rc=$?
check "a re-apply finds a code-span target by its rendered text" 0 "${rc}"
contains "and sends Apps Script the text without backticks" "text='the status reads done'" "$(cat "${dir}/err")"
contains "and relinks the #goto- label by its text" '"bookmark": {"id": "BOOKMARK_bm-status-done"' "${out}"

# --- --apply --execute: it writes, alone or under a parent's resolved act ---

apply_acts() {   # <name> <env or ->
  run "${1}" "${2}" --apply --doc DOC_A --file "${T}/draft.md" --execute
  check "apply --execute, ${1}: exits 0" 0 "${rc}"
  check "apply --execute, ${1}: runs addBookmarks, then sends the relink batch" $'script scripts run\ndocs documents batchUpdate' "$(writes "${dir}")"
  check "apply --execute, ${1}: reports dry_run 0" 0 "$(last_json "${out}")"
}
apply_acts "alone" -
apply_acts "under a parent's DRY_RUN=0" DRY_RUN=0
check "the batch points the #goto- run at the bookmark addBookmarks returned" '"id.abc"' \
  "$(jq -s '[.[] | select(.[0:3] == ["docs", "documents", "batchUpdate"])] | first | .[index("--json") + 1] | fromjson | [.requests[].updateTextStyle.textStyle.link.bookmark.id | select(.)] | first' "${dir}/calls.jsonl")"

# --- --configure: the config changes only under --execute ---

config_of() {   # <dir>
  jq -c . "${1}/home/.local/share/ari-hemingway/gdoc_bookmarks.json"
}
run "configure no flag" - --configure --script-id SCRIPT_B
check "configure with no flag exits 0" 0 "${rc}"
check "configure with no flag leaves the config as it was" '{"scriptId":"SCRIPT_A","deploymentId":"DEPLOY_A"}' "$(config_of "${dir}")"
contains "and logs what it would record" "would record bookmark setup | path='${dir}/home/.local/share/ari-hemingway/gdoc_bookmarks.json' scriptId='SCRIPT_B'" "$(cat "${dir}/err")"
run "configure execute" - --configure --script-id SCRIPT_B --execute
check "configure --execute records the new id and drops the old project's deployment" '{"scriptId":"SCRIPT_B"}' "$(config_of "${dir}")"
check "configure --execute reports dry_run 0" 0 "$(last_json "${out}")"
out="$(env HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}" \
  zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" --configure --script-id SCRIPT_B --execute 2>"${dir}/err2")"
contains "a repeat of configure --execute changes nothing" "Nothing to change | changes='0'" "$(cat "${dir}/err2")"

# --- --check-setup: read-only, and the commands it prints act ---

run "check-setup execute" - --check-setup --execute
check "check-setup --execute is refused" 1 "${rc}"
check "and calls no gws" 0 "$(calls_of "${dir}" "script scripts run")"
dir="$(new_case "check-setup")"
print -r -- '{"scriptId": "SCRIPT_A"}' > "${dir}/home/.local/share/ari-hemingway/gdoc_bookmarks.json"
print -r -- '{"scopes": ["https://www.googleapis.com/auth/documents", "https://www.googleapis.com/auth/drive", "https://www.googleapis.com/auth/script.projects", "https://www.googleapis.com/auth/script.deployments"]}' > "${dir}/auth-status-.json"
jq -n --rawfile gs "${SKILL_DIR}/bin/gas/Bookmarks.gs" --rawfile manifest "${SKILL_DIR}/bin/gas/appsscript.json" \
  '{files: [{name: "Bookmarks", source: $gs}, {name: "appsscript", source: $manifest}]}' > "${dir}/script-projects-getContent.json"
out="$(env HOME="${dir}/home" XDG_CONFIG_HOME="${REAL_CONFIG_HOME}" FAKE_GWS_DIR="${dir}" PATH="${T}/bin:${PATH}" \
  zsh "${T}/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh" --check-setup 2>"${dir}/err")"; rc=$?
check "check-setup with no versioned deployment exits 1" 1 "${rc}"
lacks "check-setup logs no dry-run line" "Dry run" "$(cat "${dir}/err")"
contains "the --configure it prints carries --execute" "--configure --script-id SCRIPT_A --deployment-id <deploymentId from the reply> --execute" "${out}"

print -r -- "pass=${pass} fail=${fail}"
(( fail == 0 ))
