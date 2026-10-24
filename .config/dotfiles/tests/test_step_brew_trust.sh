#!/usr/bin/env bash
# brew_drift trust notes: a declared third-party tap without `trusted: true` is a note unless
# brew's own trust.json already trusts the tap, or every declared item from it.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
GLOBAL="${HOME}/.config/new-machine/Brewfile"
TRUST="${XDG_CONFIG_HOME}/homebrew/trust.json"
mkdir -p "$(dirname "${TRUST}")"

check_drift() { bump_now_secs 60; nm check --only brew,brew_drift --json; out_json > /dev/null; }
untrusted() { jq -r '.brew.untrusted_taps | join(",")' "${FIX}/out.json"; }

printf '%s\n' 'tap "hashicorp/tap"' 'brew "hashicorp/tap/terraform"' 'brew "hashicorp/tap/vault"' >> "${GLOBAL}"

check_drift
assert_eq "untrusted tap, no trust.json → warn" warn "$(step_get brew_drift .status)"
assert_eq "reason drift_notes" drift_notes "$(step_get brew_drift .reason)"
assert_eq "untrusted_taps names it" hashicorp/tap "$(untrusted)"
assert_contains "detail says lacks trusted: true" "$(step_get brew_drift .detail)" "hashicorp/tap lacks trusted: true"

# One of two declared items trusted is not enough: the other one would still prompt.
jq -n '{trustedtaps: [], trustedformulae: ["hashicorp/tap/terraform"], trustedcasks: []}' > "${TRUST}"
check_drift
assert_eq "one item trusted → still warn" warn "$(step_get brew_drift .status)"
assert_eq "untrusted_taps still names it" hashicorp/tap "$(untrusted)"

# Every declared item trusted: brew never prompts on this machine, so nothing to note.
jq -n '{trustedtaps: [], trustedformulae: ["hashicorp/tap/terraform", "hashicorp/tap/vault"], trustedcasks: []}' > "${TRUST}"
check_drift
assert_eq "all items trusted → ok" ok "$(step_get brew_drift .status)"
assert_eq "reason satisfied" satisfied "$(step_get brew_drift .reason)"
assert_eq "untrusted_taps empty" "" "$(untrusted)"

# The tap itself trusted in trust.json, the pre-existing path.
jq -n '{trustedtaps: ["hashicorp/tap"], trustedformulae: [], trustedcasks: []}' > "${TRUST}"
check_drift
assert_eq "tap trusted in trust.json → ok" ok "$(step_get brew_drift .status)"
assert_eq "untrusted_taps empty (tap)" "" "$(untrusted)"

# A tap line with no declared items from it cannot be vouched for by items.
rm -f "${TRUST}"
printf '%s\n' 'tap "jurplel/tap"' >> "${GLOBAL}"
jq -n '{trustedtaps: [], trustedformulae: ["hashicorp/tap/terraform", "hashicorp/tap/vault"], trustedcasks: []}' > "${TRUST}"
check_drift
assert_eq "itemless tap → warn" warn "$(step_get brew_drift .status)"
assert_eq "only the itemless tap is noted" jurplel/tap "$(untrusted)"

if (( FAIL > 0 )); then jq -c '.steps[] | select(.step=="brew_drift") | {status, reason, detail}' "${FIX}/out.json" >&2; fi
report
