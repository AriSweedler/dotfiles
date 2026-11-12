#!/usr/bin/env bash
# `dotfiles pull`: local commits replay onto origin's when they touch different files; a replay
# that conflicts is aborted with the tier as it was and the conflicting file named. No init runs
# after it (test_pull_changes.sh covers what it reports instead).
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
assert_eq "clean replay: exit 0" 0 "${RC}"
assert_contains "clean replay: the pulled path counted" "${OUT}" "pulled 1 changed path"
assert_contains "clean replay: no step watches it" "${OUT}" "no step watches these paths: nothing to apply"
assert_no_file "clean replay: init did not run" "${ARI_DOTFILES_STATE_DIR}/runs"
assert_no_file "clean replay: no init result" "${ARI_DOTFILES_STATE_DIR}/last_result.json"

# A fork-point the reflog invents: origin/main once pointed at a local commit (nix_port clones from the
# bare repo, then re-points origin at the remote), so a fork-point rebase would drop every local commit
# up to it. The replay starts at the merge-base instead.
local_commit .config/pull-fp-1.txt one "local one"
local_commit .config/pull-fp-2.txt two "local two"
real_origin="$(df_git rev-parse origin/main)"
df_git update-ref --create-reflog -m "clone: from the bare repo" refs/remotes/origin/main "$(df_git rev-parse HEAD)"
df_git update-ref --create-reflog -m "fetch: forced-update" refs/remotes/origin/main "${real_origin}"
remote_commit .config/pull-fp-remote.txt remote "remote after the clone"
bump_now_secs 60
nm pull
assert_eq "fork-point trap: exit 0" 0 "${RC}"
assert_contains "fork-point trap: the first local commit survives" "$(df_git log --format=%s origin/main..HEAD)" "local one"
assert_contains "fork-point trap: the second local commit survives" "$(df_git log --format=%s origin/main..HEAD)" "local two"
assert_file "fork-point trap: origin's file checked out" "${HOME}/.config/pull-fp-remote.txt"

# ── Dev repos: fast-forwarded to their origin/main, or left alone with a warning ─────────────

# dev_new PATH: a dev repo checkout at HOME/PATH with one commit, its origin a local bare repo.
dev_new() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/${1//\//-}.git"
  mkdir -p "${dir}"
  git init -q --initial-branch=main "${dir}"
  git -C "${dir}" config user.name test && git -C "${dir}" config user.email test@example.com
  printf 'one\n' > "${dir}/f"
  git -C "${dir}" add f && git -C "${dir}" commit -q -m one
  git init -q --bare --initial-branch=main "${bare}"
  git -C "${dir}" remote add origin "${bare}"
  git -C "${dir}" push -q origin main
}
# dev_origin_commit PATH: a commit lands on the dev repo's origin that the checkout has not fetched.
dev_origin_commit() {
  local bare="${FIX}/remotes/${1//\//-}.git" clone="${FIX}/dev-clone-${1//\//-}"
  rm -rf "${clone}"
  git clone -q "${bare}" "${clone}"
  printf 'more\n' >> "${clone}/f"
  git -C "${clone}" -c user.name=test -c user.email=test@example.com commit -q -am more
  git -C "${clone}" push -q origin main
}
dev_head() { git -C "${HOME}/$1" rev-parse HEAD; }

for d in behind dirty diverged detached; do dev_new ".config/dev-${d}"; done
world_dev_repos .config/dev-behind .config/dev-dirty .config/dev-diverged .config/dev-detached
for d in behind dirty diverged detached; do dev_origin_commit ".config/dev-${d}"; done
printf 'edit\n' >> "${HOME}/.config/dev-dirty/f"
printf 'ours\n' > "${HOME}/.config/dev-diverged/g"
git -C "${HOME}/.config/dev-diverged" add g && git -C "${HOME}/.config/dev-diverged" commit -q -m ours
git -C "${HOME}/.config/dev-detached" checkout -q --detach
want="$(git -C "${FIX}/dev-clone-.config-dev-behind" rev-parse HEAD)"
before_behind="$(dev_head .config/dev-behind)"
before_dirty="$(dev_head .config/dev-dirty)"
before_diverged="$(dev_head .config/dev-diverged)"
before_detached="$(dev_head .config/dev-detached)"

bump_now_secs 60
nm pull --dry-run
assert_eq "dev repos, dry run: exit 0" 0 "${RC}"
assert_contains "dev repos, dry run: names what would move" "${OUT}" "dev repo (would move) .config/dev-behind"
assert_eq "dev repos, dry run: nothing moved" "${before_behind}" "$(dev_head .config/dev-behind)"

bump_now_secs 60
nm pull
assert_eq "dev repos: exit 0" 0 "${RC}"
assert_eq "dev repos: the behind checkout fast-forwarded" "${want}" "$(dev_head .config/dev-behind)"
assert_contains "dev repos: the range is reported" "${OUT}" "dev repo .config/dev-behind: "
assert_eq "dev repos: a dirty checkout is untouched" "${before_dirty}" "$(dev_head .config/dev-dirty)"
assert_contains "dev repos: a dirty checkout is warned about" "${ERR}" "uncommitted changes | repo='.config/dev-dirty'"
assert_eq "dev repos: a diverged checkout is untouched" "${before_diverged}" "$(dev_head .config/dev-diverged)"
assert_contains "dev repos: a diverged checkout is warned about" "${ERR}" "has commits origin/main lacks | repo='.config/dev-diverged'"
assert_eq "dev repos: a detached checkout is untouched" "${before_detached}" "$(dev_head .config/dev-detached)"
assert_contains "dev repos: a detached checkout is warned about" "${ERR}" "not on main (detached HEAD) | repo='.config/dev-detached'"

bump_now_secs 60
nm pull
assert_not_contains "dev repos: a second pull moves nothing" "${OUT}" "dev repo .config/dev-behind"

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
