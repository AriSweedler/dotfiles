#!/usr/bin/env bash
# dotfiles_repo: bare clone + checkout + hooksPath from an empty HOME, conflicts left intact,
# hooksPath repaired alone, dirty vs untracked, dry-run reaches no network.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"

check_repo() { bump_now_secs 60; nm check --only dotfiles_repo --json; out_json > /dev/null; }
apply_repo() { bump_now_secs 60; nm apply dotfiles_repo; }

check_repo
assert_eq "empty HOME → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason missing_bare_repo" missing_bare_repo "$(step_get dotfiles_repo .reason)"

apply_repo
assert_eq "apply exits 0" 0 "${RC}"
assert_file "bare repo cloned" "${NEW_MACHINE_DF_GIT_DIR}/HEAD"
assert_file "worktree checked out" "${HOME}/.config/zsh/plugins/log.zsh"
assert_file "worktree has the seed .zshenv" "${HOME}/.zshenv"
assert_eq "hooksPath set" "${NEW_MACHINE_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
check_repo
assert_eq "re-check ok" ok "$(step_get dotfiles_repo .status)"
assert_eq "curl never called" "" "$(shim_log curl)"

# A pre-existing file the checkout would overwrite stops the apply and is never moved.
world_empty_home
printf 'mine, not yours\n' > "${HOME}/.zshenv"
apply_repo
assert_eq "conflicting checkout exits 1" 1 "${RC}"
assert_eq "conflicting file intact" "mine, not yours" "$(cat "${HOME}/.zshenv")"
run_dir="$(newest_run_dir)"
assert_contains "conflicting file is named" "${ERR}$(cat "${run_dir}"/dotfiles_repo*.log 2>/dev/null)$(cat "${run_dir}/dotfiles_repo.result.json" 2>/dev/null)" ".zshenv"
out_json > /dev/null 2>&1 || true
rm -f "${HOME}/.zshenv"
rm -rf "${NEW_MACHINE_DF_GIT_DIR}"
apply_repo
assert_eq "clean apply after removing the conflict" 0 "${RC}"

# hooksPath alone is repaired without touching the checkout.
df_git config --local --unset core.hooksPath
check_repo
assert_eq "unset hooksPath → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason hooks_path" hooks_path "$(step_get dotfiles_repo .reason)"
head_before="$(df_git rev-parse HEAD)"
zshenv_before="$(sha256 "${HOME}/.zshenv")"
apply_repo
assert_eq "hooks apply exits 0" 0 "${RC}"
assert_eq "hooksPath restored" "${NEW_MACHINE_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
assert_eq "HEAD unchanged" "${head_before}" "$(df_git rev-parse HEAD)"
assert_eq "worktree unchanged" "${zshenv_before}" "$(sha256 "${HOME}/.zshenv")"

printf '\n# local edit\n' >> "${HOME}/.zshenv"
check_repo
assert_eq "dirty worktree → warn" warn "$(step_get dotfiles_repo .status)"
assert_eq "reason uncommitted" uncommitted "$(step_get dotfiles_repo .reason)"
df_git checkout -q -- "${HOME}/.zshenv"

printf 'scratch\n' > "${HOME}/untracked.txt"
check_repo
assert_eq "untracked file alone → ok" ok "$(step_get dotfiles_repo .status)"

# `git ls-files` is scoped to the cwd; a check started from a subdirectory of HOME with no tracked
# files under it (the real machine: a terminal inside a source checkout) must still see the index.
pushd "${HOME}/Desktop" > /dev/null || abort "no Desktop in the fake HOME"
check_repo
popd > /dev/null || abort "popd failed"
assert_eq "check from a work-tree subdirectory → ok" ok "$(step_get dotfiles_repo .status)"
assert_eq "check from a work-tree subdirectory keeps reason clean" clean "$(step_get dotfiles_repo .reason)"

world_empty_home
bump_now_secs 60
nm setup --only dotfiles_repo --dry-run
if (( RC == 0 || RC == 1 )); then pass "dry-run exits by verdict (rc=${RC})"; else fail "dry-run exits by verdict" "rc=${RC}"; fi
assert_no_file "dry-run clones nothing" "${NEW_MACHINE_DF_GIT_DIR}"
assert_contains "dry-run says what it would do" "${ERR}" "would run apply::dotfiles_repo"
assert_eq "dry-run never reaches curl" "" "$(shim_log curl)"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
