#!/usr/bin/env bash
# A concurrent brew makes the brew steps `error brew_busy`; nothing else is affected.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
start_busy_brew
busy_pid="${WORLD_PIDS[0]}"

nm check --json
assert_eq "check exits 2" 2 "${RC}"
f="$(out_json)"
for step in brew_pkgs brew_drift; do
  assert_eq "${step} is error" error "$(step_get "${step}" .status)"
  assert_eq "${step} reason brew_busy" brew_busy "$(step_get "${step}" .reason)"
  assert_contains "${step} detail names the pid" "$(step_get "${step}" .detail)" "${busy_pid}"
done
assert_json "every step has a status" "${f}" '[.steps[] | select((.status // "") == "")] | length' 0
assert_json "12 steps ran" "${f}" '.steps|length' 12
assert_eq "brew itself is ok" ok "$(step_get brew .status)"
assert_json "other steps still ran" "${f}" '[.steps[] | select(.step=="dotfiles_repo" or .step=="claude" or .step=="bob_neovim") | .status] | all(. != "skip" and . != "error")' true
assert_no_mutation "busy check is read-only"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${f}" >&2; fi
report
