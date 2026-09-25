#!/usr/bin/env bash
# ssh_key: skips unconfigured, warns without a path, errors without an agent, fails when the key
# is not in the agent, and loads it through an askpass helper fed by 1Password (the op shim). The
# check never calls op; the passphrase never reaches argv or a log.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
KEY="${HOME}/.ssh/id_test"
PASSPHRASE='open sesame'

check_key() { bump_now_secs 60; nm check --only ssh_key --json; out_json > /dev/null; }

check_key
assert_eq "unconfigured → skip" skip "$(step_get ssh_key .status)"
assert_eq "reason not_configured" not_configured "$(step_get ssh_key .reason)"

export ARI_DOTFILES_SSH_KEY_OP_ITEM="SSH key: tests" ARI_DOTFILES_SSH_KEY_OP_VAULT=Employee
check_key
assert_eq "no path → warn" warn "$(step_get ssh_key .status)"
assert_eq "reason path_unknown" path_unknown "$(step_get ssh_key .reason)"
assert_eq "path_unknown is manual" true "$(step_get ssh_key .manual)"

export ARI_DOTFILES_SSH_KEY_PATH="${KEY}"
check_key
assert_eq "missing key file → fail" fail "$(step_get ssh_key .status)"
assert_eq "reason key_file_missing" key_file_missing "$(step_get ssh_key .reason)"
assert_eq "key_file_missing is manual" true "$(step_get ssh_key .manual)"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
ssh-keygen -q -t ed25519 -N "${PASSPHRASE}" -C tests -f "${KEY}"
FINGERPRINT="$(ssh-keygen -lf "${KEY}" | awk '{print $2}')"
check_key
assert_eq "no agent → error" error "$(step_get ssh_key .status)"
assert_eq "reason agent_unreachable" agent_unreachable "$(step_get ssh_key .reason)"

# An agent of the test's own; hermetic_env hands only this one to the code. Its socket takes a
# short path of its own: a unix socket path is capped at 104 bytes and the world's is longer.
unset SSH_AUTH_SOCK SSH_AGENT_PID
AGENT_DIR="$(mktemp -d /tmp/nm-agent.XXXXXX)"
trap 'rm -rf "${AGENT_DIR}"; world_teardown' EXIT
eval "$(ssh-agent -s -a "${AGENT_DIR}/sock")" > /dev/null
WORLD_PIDS+=("${SSH_AGENT_PID}")
export TEST_SSH_AUTH_SOCK="${SSH_AUTH_SOCK}"
assert_eq "the test's agent answers" "The agent has no identities." "$(ssh-add -l 2>&1)"
check_key
assert_eq "key not in the agent → fail" fail "$(step_get ssh_key .status)"
assert_eq "reason not_loaded" not_loaded "$(step_get ssh_key .reason)"
assert_contains "fix is the apply" "$(step_get ssh_key .fix)" "apply ssh_key"
assert_eq "the check never calls 1Password" "" "$(shim_log op)"

shim_remove op
check_key
assert_eq "no op → fail" fail "$(step_get ssh_key .status)"
assert_eq "reason op_missing" op_missing "$(step_get ssh_key .reason)"
assert_eq "op_missing is manual" true "$(step_get ssh_key .manual)"
assert_contains "fix installs the CLI" "$(step_get ssh_key .fix)" "brew install 1password-cli"
shim_add op

export OP_SHIM_PASSPHRASE="${PASSPHRASE}"
bump_now_secs 60
nm apply ssh_key
assert_eq "apply exits 0" 0 "${RC}"
assert_contains "op asked for the password field, revealed" "$(shim_log op)" "--fields password --reveal"
assert_contains "op asked for the item" "$(shim_log op)" "SSH key: tests"
assert_contains "op asked in the vault" "$(shim_log op)" "--vault Employee"
assert_not_contains "passphrase never on argv" "$(shim_log op)" "${PASSPHRASE}"
assert_not_contains "passphrase never logged" "${ERR}$(cat "$(newest_run_dir)"/ssh_key*.log 2>/dev/null)" "${PASSPHRASE}"
assert_contains "key is in the agent" "$(ssh-add -l)" "${FINGERPRINT}"
check_key
assert_eq "loaded → ok" ok "$(step_get ssh_key .status)"

shim_logs_reset
bump_now_secs 60
nm apply ssh_key --json
assert_eq "second apply exits 0" 0 "${RC}"
f="$(out_json)"
assert_json "second apply applies nothing" "${f}" '[.steps[] | select(.applied == true or .applied == "would_apply")] | length' 0
assert_eq "second apply asks 1Password nothing" "" "$(shim_log op)"

ssh-add -d "${KEY}" 2>/dev/null
shim_logs_reset
bump_now_secs 60
nm apply ssh_key --dry-run
assert_contains "dry-run says what it would do" "${ERR}$(cat "$(newest_run_dir)"/ssh_key*.log 2>/dev/null)" "would ssh-add"
assert_eq "dry-run asks 1Password nothing" "" "$(shim_log op)"
assert_not_contains "dry-run loads nothing" "$(ssh-add -l 2>/dev/null || true)" "${FINGERPRINT}"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, fix}' "${FIX}/out.json" >&2; fi
report
