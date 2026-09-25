#!/usr/bin/env bash
# One Desktop file, rewritten only when the set of failing tuples changes; deletion is
# acknowledgement; edited reports are renamed, never clobbered; a pass archives the file.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
world_bundle_check mixed
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export BOB_SHIM_LS="Installed: v0.11.2 Used"
export ARI_DOTFILES_INVOKED_BY=launchd
REPORT="${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.md"
STATE="${ARI_DOTFILES_STATE_DIR}"
LR="${STATE}/last_result.json"

verify() { bump_now_secs 60; shim_logs_reset; nm verify "$@"; }
lr() { jq -r "$1" "${LR}"; }
count_reports() { local n=0 f; for f in "${STATE}"/reports/*.md; do [[ -e "${f}" ]] && n=$((n + 1)); done; printf '%s' "${n}"; }

verify
assert_eq "first verify exits 1" 1 "${RC}"
assert_file "report written" "${REPORT}"
sha1="$(sha256 "${REPORT}")"
fp1="$(lr .fingerprint)"
first_seen1="$(lr .first_seen)"

bump_now 7
verify
assert_eq "same fingerprint a week later" "${fp1}" "$(lr .fingerprint)"
assert_eq "report not rewritten" "${sha1}" "$(sha256 "${REPORT}")"
assert_json "weeks_failing 2" "${LR}" '.weeks_failing' 2
assert_eq "first_seen kept" "${first_seen1}" "$(lr .first_seen)"
assert_contains "notifier says still failing" "$(shim_log terminal-notifier)" "still failing since ${first_seen1}"

rm -f "${REPORT}"
verify
assert_no_file "deleted report is not recreated (acknowledged)" "${REPORT}"
assert_json "weeks_failing 3" "${LR}" '.weeks_failing' 3

verify --force-report
assert_file "--force-report recreates it" "${REPORT}"
assert_eq "fingerprint unchanged after force" "${fp1}" "$(lr .fingerprint)"

fixture_add_formula cowsay2
verify
fp2="$(lr .fingerprint)"
if [[ "${fp2}" != "${fp1}" ]]; then pass "new undeclared item changes the fingerprint"; else fail "new undeclared item changes the fingerprint" "unchanged ${fp1}"; fi
# Every render is archived: the first, the forced re-render, the Desktop copy moved aside (its
# first_seen name was taken by a different render, so it got a numbered one), and the new one.
assert_eq "four archived reports" 4 "$(count_reports)"
assert_contains "new report names the new item" "$(cat "${REPORT}")" "cowsay2"
assert_contains "new report has the new-since line" "$(cat "${REPORT}")" "New since the last run"
assert_json "weeks_failing reset to 1" "${LR}" '.weeks_failing' 1
assert_json "first_seen is the new run's day" "${LR}" '.first_seen' "$(TZ=UTC date -r "${ARI_DOTFILES_NOW}" '+%Y-%m-%d')"
assert_contains "notifier announces the new report" "$(shim_log terminal-notifier)" "problems"

printf '\nmy notes\n' >> "${REPORT}"
fixture_add_formula cowsay3
verify
edited=("${ARI_DOTFILES_DESKTOP_DIR}"/new-machine-FAILED.*.edited.md)
assert_eq "edited report renamed aside" 1 "${#edited[@]}"
if [[ "$(basename "${edited[0]}")" =~ ^new-machine-FAILED\.[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9a-f]{8}\.edited\.md$ ]]; then pass "edited file named new-machine-FAILED.<date>-<fp8>.edited.md"
else fail "edited file named new-machine-FAILED.<date>-<fp8>.edited.md" "${edited[0]}"; fi
assert_contains "edited file keeps the notes" "$(cat "${edited[0]}")" "my notes"
assert_file "new report written" "${REPORT}"
assert_contains "new report names cowsay3" "$(cat "${REPORT}")" "cowsay3"
rm -f "${edited[0]}"

world_use_fixture satisfied
verify
assert_eq "pass exits 0" 0 "${RC}"
assert_no_file "report moved off the Desktop on pass" "${REPORT}"
assert_eq "archives keep every report" 5 "$(count_reports)"
assert_file "last-ok stamped" "${STATE}/last-ok"
assert_json "fingerprint cleared" "${LR}" '.fingerprint' ""
assert_json "status ok or warn" "${LR}" '.status == "ok" or .status == "warn"' true
assert_contains "notifier says verified OK" "$(shim_log terminal-notifier)" "verified OK"

world_use_fixture drift
world_bundle_check mixed
verify
assert_file "report back after drift returns" "${REPORT}"
printf '\nmore notes\n' >> "${REPORT}"
world_use_fixture satisfied
verify
assert_eq "pass with an edited report exits 0" 0 "${RC}"
assert_file "edited report left on the Desktop" "${REPORT}"
assert_contains "trail notes the edited report" "$(cat "${STATE}/verify.log")${ERR}" "left edited report"
rm -f "${REPORT}"

world_use_fixture drift
world_bundle_check mixed
verify
sha_a="$(sha256 "${REPORT}")"
first_seen_a="$(lr .first_seen)"
printf '\n# local edit\n' >> "${HOME}/.config/new-machine/local-dotfiles-exclude"
verify
assert_eq "a warn-only change leaves the report alone" "${sha_a}" "$(sha256 "${REPORT}")"
assert_eq "first_seen unchanged by a warn-only change" "${first_seen_a}" "$(lr .first_seen)"

# A foreign file at the canonical path: ours goes beside it under new-machine-FAILED.<fp8>.md, and
# that copy gets the same protection — a marker-less edit of it is never overwritten when the
# fingerprint recurs; the new report takes a numbered name instead.
rm -f "${REPORT}"
printf 'not ours\n' > "${REPORT}"
fixture_add_formula cowsay4
verify
assert_eq "foreign file left at the canonical path" "not ours" "$(cat "${REPORT}")"
fp8="$(lr .fingerprint | cut -c1-8)"
COLL="${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.${fp8}.md"
assert_file "report written beside the foreign file" "${COLL}"
assert_eq "last_result points at the collision copy" "${COLL}" "$(lr .report_path)"
{ printf 'my triage\n'; tail -n +2 "${COLL}"; printf '\ncollision notes\n'; } > "${COLL}.tmp"
mv "${COLL}.tmp" "${COLL}"
fixture_add_formula cowsay5
verify
fixture_remove_formula cowsay5
verify
assert_contains "marker-edited collision report keeps its notes" "$(cat "${COLL}")" "collision notes"
assert_file "recurring fingerprint writes a numbered copy" "${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.${fp8}.2.md"
assert_eq "numbered copy is the current report" "${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.${fp8}.2.md" "$(lr .report_path)"
assert_no_mutation "verify runs never mutate"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
