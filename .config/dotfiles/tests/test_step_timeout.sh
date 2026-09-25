#!/usr/bin/env bash
# The watchdog: a hung check becomes `error timed_out`, the run continues, no sleeper survives —
# whether brew hangs as the check's direct child or two forks down.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_home_baseline
export NEW_MACHINE_CHECK_TIMEOUT_SECS=1

sleepers() { pgrep -f 'sleep 30' | sort || true; }
# `sleep 30` processes that appeared since <before>, after giving the kill a moment to land.
new_sleepers() { sleep 0.5; comm -13 <(printf '%s\n' "$1") <(sleepers); }

touch "${BREW_SHIM_FIXTURE}/bundle_check.hang"
before="$(sleepers)"
t0="$(date +%s)"
nm check --json
t1="$(date +%s)"
assert_eq "check exits 2" 2 "${RC}"
f="$(out_json)"
assert_eq "brew_pkgs is error" error "$(step_get brew_pkgs .status)"
assert_eq "brew_pkgs reason timed_out" timed_out "$(step_get brew_pkgs .reason)"
# 1 s timeout plus the 5 s KILL grace; loose because the suite runs under load.
elapsed=$((t1 - t0))
if (( elapsed < 20 )); then pass "wall time under 20 s (${elapsed}s)"; else fail "wall time under 20 s" "took ${elapsed}s"; fi
for step in brew_drift dotfiles_repo claude dotfiles_jobs; do
  status="$(step_get "${step}" .status)"
  if [[ -n "${status}" && "${status}" != null && "${status}" != skip ]]; then pass "${step} ran after the timeout (${status})"
  else fail "${step} ran after the timeout" "status='${status}'"; fi
done
assert_eq "no orphaned sleep 30 left behind" "" "$(new_sleepers "${before}")"

# brew hanging two forks down: `brew tap-info` runs inside brew::_tap_info_map inside $(...), so
# the sleeper is a grandchild of the check and only a tree kill reaches it.
world_use_fixture drift
world_bundle_check satisfied
touch "${BREW_SHIM_FIXTURE}/tapinfo.hang"
before="$(sleepers)"
bump_now_secs 60
nm check --only brew,brew_drift --json
f="$(out_json)"
assert_eq "grandchild hang: brew_drift is error" error "$(step_get brew_drift .status)"
assert_eq "grandchild hang: reason timed_out" timed_out "$(step_get brew_drift .reason)"
assert_eq "grandchild hang: no orphaned sleep 30 left behind" "" "$(new_sleepers "${before}")"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
