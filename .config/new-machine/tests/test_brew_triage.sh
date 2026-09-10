#!/usr/bin/env bash
# `brew triage`: paste-ready commands per undeclared item, the orphan recipe, ignores with
# reasons, --json == drift.json, exit code by findings, read-only.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
world_ignore global libtiff

# A row starts with the kind, then the name (column alignment may pad between them).
assert_row() {
  local name="$1" kind="$2" item="$3"
  if grep -qE "^${kind}[[:space:]]+${item//./\\.}([[:space:]]|$)" <<< "${OUT}"; then pass "${name}"
  else fail "${name}" "no row '${kind} ${item}' in:
${OUT}"; fi
}

bump_now_secs 60
nm brew triage
assert_eq "triage with drift exits 1" 1 "${RC}"
assert_row "row for formula gh" formula gh
assert_contains "every-machine command" "${OUT}" "new-machine brew decree formula:gh --global"
assert_contains "this-machine command" "${OUT}" "new-machine brew decree formula:gh --local"
assert_contains "never-declare command" "${OUT}" "new-machine brew decree formula:gh --ignore-local --reason"
assert_row "cask row" cask google-chrome
assert_contains "cask commands use the cask: prefix" "${OUT}" "new-machine brew decree cask:google-chrome --local"
assert_row "tap row" tap hashicorp/tap
assert_row "vscode row" vscode ms-python.python
assert_contains "orphan recipe" "${OUT}" "brew uninstall spacectl && brew tap spacelift-io/spacelift && brew install --cask spacelift-io/spacelift/spacectl"
assert_contains "orphan follow-up decree" "${OUT}" "new-machine brew decree cask:spacelift-io/spacelift/spacectl --local"
assert_contains "ignored section names the item" "${OUT}" "libtiff"
assert_contains "ignored section prints the reason" "${OUT}" "library brew marks on-request"

world_ignore local include
bump_now_secs 60
nm brew triage
assert_eq "triage still exits 1 with items left" 1 "${RC}"
assert_contains "ignored via include-declared names the path" "${OUT}" "include-declared ${FIX}/brew/company.Brewfile"
assert_not_contains "gh no longer offered for decree" "${OUT}" "decree formula:gh --global"

bump_now_secs 60
nm brew triage --json
assert_eq "triage --json exits 1" 1 "${RC}"
jq -S . <<< "${OUT}" > "${FIX}/triage.json" 2> "${FIX}/triage.err" || fail "triage --json is JSON" "$(cat "${FIX}/triage.err")"
bump_now_secs 60
nm check --only brew,brew_drift --json
jq -S '.brew' <<< "${OUT}" > "${FIX}/check-brew.json"
if cmp -s "${FIX}/triage.json" "${FIX}/check-brew.json"; then pass "triage --json equals drift.json"
else fail "triage --json equals drift.json" "$(diff "${FIX}/triage.json" "${FIX}/check-brew.json" | head -n 20)"; fi
assert_json "json carries the ignored list" "${FIX}/triage.json" '[.ignored[] | .name] | index("gh") != null' true
assert_no_mutation "triage is read-only"

world_use_fixture satisfied
bump_now_secs 60
nm brew triage
assert_eq "triage on a clean machine exits 0" 0 "${RC}"
assert_not_contains "no decree commands offered" "${OUT}" "brew decree"

report
