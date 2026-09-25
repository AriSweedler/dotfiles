#!/usr/bin/env bash
# brew_drift: fail on anything a human must decide, warn on bookkeeping notes, ok when every
# installed item is declared or ignored; `new` follows the previous run's undeclared set.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
IGNORE="${HOME}/.config/new-machine/Brewfile.ignore"

check_drift() { bump_now_secs 60; nm check --only brew,brew_drift --json; out_json > /dev/null; }

check_drift
assert_eq "drift exits 1" 1 "${RC}"
assert_eq "brew_drift is fail" fail "$(step_get brew_drift .status)"
assert_eq "reason drift" drift "$(step_get brew_drift .reason)"
assert_eq "drift is manual" true "$(step_get brew_drift .manual)"
assert_contains "fix names triage" "$(step_get brew_drift .fix)" "brew triage"
assert_json "items cover undeclared + orphan" "${FIX}/out.json" '.steps[] | select(.step=="brew_drift") | .items | length' 13
assert_json "everything is new on the first run" "${FIX}/out.json" '.brew.undeclared | all(.new == true)' true

mkdir -p "${ARI_DOTFILES_STATE_DIR}"
jq -n '{schema: 1, status: "fail", fingerprint: "0123456789abcdef", brew_undeclared: ["formula/gh", "cask/google-chrome"]}' > "${ARI_DOTFILES_STATE_DIR}/last_result.json"
check_drift
assert_json "previously seen items are not new" "${FIX}/out.json" '[.brew.undeclared[] | select(.new == false) | .kind + "/" + .name] | sort | join(",")' "cask/google-chrome,formula/gh"
assert_json "only the delta is new" "${FIX}/out.json" '[.brew.undeclared[] | select(.new == true)] | length' 10
rm -f "${ARI_DOTFILES_STATE_DIR}/last_result.json"

# Everything ignored (and the orphan repaired) is a clean machine.
fixture_remove_formula spacectl spacelift-io/spacelift/spacectl
printf '%s\n' \
  'formula gh                         # company tooling' \
  'formula python@3.10                # pinned interpreter' \
  'formula buildkite/buildkite/bk@3   # company tooling' \
  'formula libtiff                    # library' \
  'cask google-chrome                 # browser' \
  'cask instant-space-switcher        # utility' \
  'tap buildkite/buildkite            # company tooling' \
  'tap hashicorp/tap                  # terraform' \
  'tap jurplel/tap                    # instant-space-switcher' \
  'tap spacelift-io/spacelift         # spacectl' > "${FIX}/ignore.base"
{ cat "${FIX}/ignore.base"; printf '%s\n' 'vscode golang.go                   # editor' 'vscode ms-python.python            # editor'; } > "${IGNORE}"
check_drift
assert_eq "all-ignored exits 0" 0 "${RC}"
assert_eq "all-ignored is ok" ok "$(step_get brew_drift .status)"
assert_json "ignored count" "${FIX}/out.json" '.brew.counts.ignored' 12
assert_json "nothing undeclared" "${FIX}/out.json" '.brew.undeclared | length' 0

printf '%s\n' 'formula nosuch   # stale entry' >> "${IGNORE}"
check_drift
assert_eq "notes-only exits 0" 0 "${RC}"
assert_eq "notes-only is warn" warn "$(step_get brew_drift .status)"
assert_eq "reason drift_notes" drift_notes "$(step_get brew_drift .reason)"
assert_json "unresolvable_ignore names it" "${FIX}/out.json" '[.brew.unresolvable_ignore[] | .name] | join(",")' nosuch

cp "${FIX}/ignore.base" "${IGNORE}"
shim_remove code
check_drift
assert_eq "code absent exits 0" 0 "${RC}"
assert_eq "code absent does not raise the status" ok "$(step_get brew_drift .status)"
assert_json "vscode_skipped flagged" "${FIX}/out.json" '.brew.vscode_skipped' true
assert_no_mutation "drift checks are read-only"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
