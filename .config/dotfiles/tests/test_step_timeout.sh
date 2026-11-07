#!/usr/bin/env bash
# The watchdog: a hung check becomes `error timed_out`, the run continues, no sleeper survives —
# whether the hung command is the check's direct child or further down its tree.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_home_baseline
export ARI_DOTFILES_CHECK_TIMEOUT_SECS=1

sleepers() { pgrep -f 'sleep 30' | sort || true; }
# `sleep 30` processes that appeared since <before>, after giving the kill a moment to land.
new_sleepers() { sleep 0.5; comm -13 <(printf '%s\n' "$1") <(sleepers); }

before="$(sleepers)"
t0="$(date +%s)"
NVIM_SHIM_HANG=1 nm check --json
t1="$(date +%s)"
assert_eq "check exits 2" 2 "${RC}"
f="$(out_json)"
assert_eq "neovim is error" error "$(step_get neovim .status)"
assert_eq "neovim reason timed_out" timed_out "$(step_get neovim .reason)"
# 1 s timeout plus the 5 s KILL grace; loose because the suite runs under load.
elapsed=$((t1 - t0))
if (( elapsed < 20 )); then pass "wall time under 20 s (${elapsed}s)"; else fail "wall time under 20 s" "took ${elapsed}s"; fi
for step in dotfiles_repo claude dotfiles_jobs karabiner; do
  status="$(step_get "${step}" .status)"
  if [[ -n "${status}" && "${status}" != null && "${status}" != skip ]]; then pass "${step} ran after the timeout (${status})"
  else fail "${step} ran after the timeout" "status='${status}'"; fi
done
assert_eq "no orphaned sleep 30 left behind" "" "$(new_sleepers "${before}")"

# nvim hanging a fork further down: the sleeper is a grandchild of the check's command, so only
# a tree kill reaches it.
before="$(sleepers)"
bump_now_secs 60
NVIM_SHIM_HANG=deep nm check --only neovim --json
f="$(out_json)"
assert_eq "grandchild hang: neovim is error" error "$(step_get neovim .status)"
assert_eq "grandchild hang: reason timed_out" timed_out "$(step_get neovim .reason)"
assert_eq "grandchild hang: no orphaned sleep 30 left behind" "" "$(new_sleepers "${before}")"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
