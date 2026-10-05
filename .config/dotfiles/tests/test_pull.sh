#!/usr/bin/env bash
# `dotfiles pull`: local commits replay onto origin's when they touch different files; a replay
# that conflicts is aborted with the tier as it was and the conflicting file named.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline

REMOTE="${FIX}/remotes/dotfiles.git"
CLONE="${FIX}/clone"
git clone -q --bare "${ARI_DOTFILES_DF_GIT_DIR}" "${REMOTE}"
df_git remote add origin "${REMOTE}"
df_git fetch -q origin
df_git branch -q --set-upstream-to=origin/main main
git clone -q "${REMOTE}" "${CLONE}"

# remote_commit, local_commit FILE TEXT MESSAGE: a test-side commit, hooks off (the hooks are not under test).
remote_commit() {
  mkdir -p "${CLONE}/$(dirname "$1")"; printf '%s\n' "$2" > "${CLONE}/$1"
  git -C "${CLONE}" add "$1" && git -C "${CLONE}" -c core.hooksPath=/dev/null commit -q -m "$3" && git -C "${CLONE}" push -q origin main
}
local_commit() {
  mkdir -p "${HOME}/$(dirname "$1")"; printf '%s\n' "$2" > "${HOME}/$1"
  df_git add "${HOME}/$1" && df_git -c core.hooksPath=/dev/null commit -q -m "$3"
}

# Diverged, no overlap: replayed.
remote_commit .config/pull-remote.txt remote "remote change"
local_commit .config/pull-local.txt local "local change"
bump_now_secs 60
nm pull
assert_eq "clean replay: nothing behind origin" 0 "$(df_git rev-list --count HEAD..origin/main)"
assert_eq "clean replay: the local commit is on top" "local change" "$(df_git log -1 --format=%s)"
assert_eq "clean replay: one commit ahead" 1 "$(df_git rev-list --count origin/main..HEAD)"
assert_file "clean replay: origin's file checked out" "${HOME}/.config/pull-remote.txt"
assert_not_contains "clean replay: no conflict reported" "${ERR}" "conflict"

# Diverged on the same file: aborted, nothing changed.
remote_commit .config/pull-both.txt theirs "remote edit"
local_commit .config/pull-both.txt ours "local edit"
head_before="$(df_git rev-parse HEAD)"
bump_now_secs 60
nm pull
assert_eq "conflict: pull exits 1" 1 "${RC}"
assert_contains "conflict: reported" "${ERR}" "conflict"
assert_contains "conflict: the file is named" "${ERR}" ".config/pull-both.txt"
assert_eq "conflict: HEAD unchanged" "${head_before}" "$(df_git rev-parse HEAD)"
assert_eq "conflict: no rebase left in progress" "" "$(ls -d "${ARI_DOTFILES_DF_GIT_DIR}"/rebase-merge "${ARI_DOTFILES_DF_GIT_DIR}"/rebase-apply 2>/dev/null)"
assert_eq "conflict: our edit still checked out" ours "$(cat "${HOME}/.config/pull-both.txt")"

report
