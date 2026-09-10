#!/usr/bin/env bash
# `setup` from an empty HOME: clones and checks out the dotfiles, initializes the local repo,
# installs the weekly job, and converges; `setup --dry-run` on the same HOME creates nothing.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"
export BREW_SHIM_ALLOW_MUTATION=1
export BOB_SHIM_LS="Installed: v0.11.2 Used"
TEMPLATE="${NEW_MACHINE_SHARED_DIR}/local-dotfiles-exclude"
rules() { grep -vE '^[[:space:]]*(#|$)' "$1" || true; }

nm setup --json
assert_eq "setup exits 0" 0 "${RC}"
f="$(out_json)"
assert_file "bare dotfiles repo cloned" "${NEW_MACHINE_DF_GIT_DIR}/HEAD"
assert_file "worktree has the log lib" "${HOME}/.config/zsh/plugins/log.zsh"
assert_eq "df hooksPath set" "${NEW_MACHINE_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
assert_file "local-dotfiles bare repo created" "${NEW_MACHINE_LDF_GIT_DIR}/HEAD"
assert_eq "ldf hooksPath set" "${NEW_MACHINE_LDF_HOOKS}" "$(git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" config --local --get core.hooksPath)"
assert_eq "ldf info/exclude == template" "$(rules "${TEMPLATE}")" "$(rules "${NEW_MACHINE_LDF_GIT_DIR}/info/exclude")"
assert_file "weekly plist installed" "${HOME}/Library/LaunchAgents/com.$(id -un).new-machine-verify.plist"
assert_file "weekly job loaded" "${LAUNCHCTL_SHIM_STATE}/com.$(id -un).new-machine-verify"
assert_json "status ok or warn" "${f}" '.status == "ok" or .status == "warn"' true
assert_json "no step failed or errored" "${f}" '[.steps[] | select(.status=="fail" or .status=="error") | .step + "=" + .reason] | join(",")' ""
assert_json "no step aborted" "${f}" '[.steps[] | select(.status=="skip" and .reason=="aborted")] | length' 0
assert_json "local_dotfiles_repo reports the manual remote step" "${f}" '.steps[] | select(.step=="local_dotfiles_repo") | .reason' no_remote
assert_json "manual remote step is manual" "${f}" '.steps[] | select(.step=="local_dotfiles_repo") | .manual' true
assert_contains "manual step: remote add" "$(jq -c '.steps[] | select(.step=="local_dotfiles_repo")' "${f}")" "git ldf remote add origin"
assert_contains "manual step: first push" "$(jq -c '.steps[] | select(.step=="local_dotfiles_repo")' "${f}")" "git ldf push --set-upstream origin main"
assert_eq "curl never called" "" "$(shim_log curl)"
assert_json "weekly_verify converged" "${f}" '.steps[] | select(.step=="weekly_verify") | .status' ok
assert_json "dotfiles_repo converged" "${f}" '.steps[] | select(.step=="dotfiles_repo") | .status' ok

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${f}" >&2; fi

# ── dry-run on a fresh empty HOME ─────────────────────────────────────────────
world_empty_home
shim_logs_reset
rm -rf "${LAUNCHCTL_SHIM_STATE:?}"/*
unset BREW_SHIM_ALLOW_MUTATION
snapshot() { find "${HOME}" -mindepth 1 -not -path "${HOME}/.local/state" -not -path "${HOME}/.local/state/*" -not -path "${HOME}/.local" | sort; }
before="$(snapshot)"
bump_now_secs 60
nm setup --dry-run
# The checks still fail on an empty HOME, so the exit code follows them (1), never 2.
if (( RC == 0 || RC == 1 )); then pass "setup --dry-run exits by verdict (rc=${RC})"; else fail "setup --dry-run exits by verdict" "rc=${RC}"; fi
assert_eq "dry-run created nothing outside the state dir" "${before}" "$(snapshot)"
assert_no_mutation "dry-run mutates nothing"
assert_contains "dry-run announces the dotfiles clone" "${ERR}" "would run apply::dotfiles_repo"
assert_no_file "dry-run cloned nothing" "${NEW_MACHINE_DF_GIT_DIR}"

report
