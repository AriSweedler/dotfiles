#!/usr/bin/env bash
# dotfiles_repo: bare clone + tracking + checkout + hooksPath from an empty HOME, conflicts left
# intact, tracking and hooksPath repaired alone, the pre-harness path renamed, dirty vs
# untracked, dry-run reaches no network.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export ARI_DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"

check_repo() { bump_now_secs 60; nm check --only dotfiles_repo --json; out_json > /dev/null; }
apply_repo() { bump_now_secs 60; nm apply dotfiles_repo; }

check_repo
assert_eq "empty HOME → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason missing_bare_repo" missing_bare_repo "$(step_get dotfiles_repo .reason)"

apply_repo
assert_eq "apply exits 0" 0 "${RC}"
assert_file "bare repo cloned" "${ARI_DOTFILES_DF_GIT_DIR}/HEAD"
assert_file "worktree checked out" "${HOME}/.config/zsh/plugins/log.zsh"
assert_file "worktree has the seed .zshenv" "${HOME}/.zshenv"
assert_eq "hooksPath set" "${ARI_DOTFILES_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
assert_eq "fetch refspec set" "+refs/heads/*:refs/remotes/origin/*" "$(df_git config --local --get remote.origin.fetch)"
assert_eq "main tracks origin" origin "$(df_git config --local --get branch.main.remote)"
assert_eq "main merges refs/heads/main" refs/heads/main "$(df_git config --local --get branch.main.merge)"
assert_eq "push url is ssh" "git@github.com:AriSweedler/dotfiles.git" "$(df_git remote get-url --push origin)"
assert_eq "origin/main fetched" "$(df_git rev-parse HEAD)" "$(df_git rev-parse refs/remotes/origin/main)"
assert_not_contains "apply runs in-process" "$(cat "$(newest_run_dir)"/dotfiles_repo*.log 2>/dev/null)" "dotfiles init"
check_repo
assert_eq "re-check ok" ok "$(step_get dotfiles_repo .status)"
assert_eq "curl never called" "" "$(shim_log curl)"

# Tracking alone is repaired without touching HEAD or the checkout.
df_git config --local --unset remote.origin.fetch
check_repo
assert_eq "missing fetch refspec → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason tracking" tracking "$(step_get dotfiles_repo .reason)"
assert_contains "detail names the key" "$(step_get dotfiles_repo .detail)" "remote.origin.fetch"
head_before="$(df_git rev-parse HEAD)"
apply_repo
assert_eq "tracking apply exits 0" 0 "${RC}"
assert_eq "fetch refspec restored" "+refs/heads/*:refs/remotes/origin/*" "$(df_git config --local --get remote.origin.fetch)"
assert_eq "HEAD unchanged by the tracking repair" "${head_before}" "$(df_git rev-parse HEAD)"

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
rm -rf "${ARI_DOTFILES_DF_GIT_DIR}"
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
assert_eq "hooksPath restored" "${ARI_DOTFILES_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
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

# A cloned dev repo needs README.md and skills/ari-dotfile--submodule-<name>/SKILL.md, linked
# into ~/.claude/skills; each gap is a manual fail naming what lacks what.
SUB="${HOME}/.config/sub"
git init -q --initial-branch=main "${SUB}"
printf 'x\n' > "${SUB}/f"
git -C "${SUB}" add f && git -C "${SUB}" commit -q -m one
world_dev_repos .config/sub
world_lock_dev .config/sub "$(git -C "${SUB}" rev-parse HEAD)"
df_git add "${HOME}/.config/dotfiles/dev-repos" "${HOME}/.config/dotfiles/nix/flake.lock"
df_git -c core.hooksPath=/dev/null commit -q -m "sub"
check_repo
assert_eq "undocumented submodule → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason submodule_undocumented" submodule_undocumented "$(step_get dotfiles_repo .reason)"
assert_eq "submodule_undocumented is manual" true "$(step_get dotfiles_repo .manual)"
assert_contains "detail: README.md missing" "$(step_get dotfiles_repo .detail)" ".config/sub lacks README.md"
assert_contains "detail: the skill missing" "$(step_get dotfiles_repo .detail)" ".config/sub lacks skills/ari-dotfile--submodule-sub/SKILL.md"
assert_contains "fix: the first gap, by the recipe" "$(step_get dotfiles_repo .fix)" "write ~/.config/sub/README.md (/ari-dotfile--submodule"
printf '# sub\n' > "${SUB}/README.md"
mkdir -p "${SUB}/skills/ari-dotfile--submodule-sub"
printf -- '---\nname: ari-dotfile--submodule-sub\n---\n' > "${SUB}/skills/ari-dotfile--submodule-sub/SKILL.md"
check_repo
assert_eq "skill not linked → still undocumented" submodule_undocumented "$(step_get dotfiles_repo .reason)"
assert_contains "detail: the link missing" "$(step_get dotfiles_repo .detail)" "~/.claude/skills lacks ari-dotfile--submodule-sub linked to ~/.config/sub/skills/ari-dotfile--submodule-sub"
assert_contains "fix: the registry's link" "$(step_get dotfiles_repo .fix)" "ari-dotfiles-skill-registry/bin/link"
mkdir -p "${HOME}/.claude/skills"
ln -s "${SUB}/skills/ari-dotfile--submodule-sub" "${HOME}/.claude/skills/ari-dotfile--submodule-sub"
check_repo
assert_eq "documented dev repo → ok" ok "$(step_get dotfiles_repo .status)"
# A commit past the one flake.lock pins: a warn, bumped by the next push.
git -C "${SUB}" commit -q --allow-empty -m two
check_repo
assert_eq "past the lock → warn" warn "$(step_get dotfiles_repo .status)"
assert_eq "reason submodule_drift" submodule_drift "$(step_get dotfiles_repo .reason)"
assert_contains "drift: the fix is a push" "$(step_get dotfiles_repo .fix)" "dotfiles push"
# The same repo as a git submodule checkout (.git a file into the shared repo's modules/): a fail
# the apply fixes by moving the git dir in, on main.
MOD="${ARI_DOTFILES_DF_GIT_DIR}/modules/.config/sub"
mkdir -p "$(dirname "${MOD}")"
git -C "${SUB}" checkout -q --detach
mv "${SUB}/.git" "${MOD}"
git --git-dir="${MOD}" config core.worktree "${SUB}"
printf 'gitdir: %s\n' "${MOD}" > "${SUB}/.git"
df_git config submodule..config/sub.url https://github.com/example/sub.git
check_repo
assert_eq "submodule layout → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason submodule_layout" submodule_layout "$(step_get dotfiles_repo .reason)"
apply_repo
assert_eq "apply after the layout fail exits 0" 0 "${RC}"
assert_eq "the git dir moved in" true "$([[ -d "${SUB}/.git" ]] && echo true || echo false)"
assert_eq "core.worktree gone" "" "$(git -C "${SUB}" config core.worktree || true)"
assert_eq "on main" main "$(git -C "${SUB}" branch --show-current)"
assert_eq "the shared repo forgot it" "" "$(df_git config --get-regexp '^submodule\.' || true)"
# Not cloned: a fail, and the apply clones it from its url.
SRC="${FIX}/sub-src"
mv "${SUB}" "${SRC}"
/usr/bin/sed -i '' "s|url = .*|url = ${SRC}|" "${HOME}/.config/dotfiles/dev-repos"
check_repo
assert_eq "not cloned → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason submodule_uninitialized" submodule_uninitialized "$(step_get dotfiles_repo .reason)"
apply_repo
[[ "${RC}" == 0 ]] || printf '%s\n' "${ERR}" | tail -n 8 >&2
assert_eq "apply clones it" "$(git -C "${SRC}" rev-parse HEAD)" "$(git -C "${SUB}" rev-parse HEAD 2>/dev/null)"
rm -rf "${SUB}" "${SRC}" "${HOME}/.claude/skills/ari-dotfile--submodule-sub" "${HOME}/.config/dotfiles/dev-repos"

# The pre-harness layout: the bare repo at ~/dotfiles. The check names it, the apply renames it
# and gives it tracking, hooks and a checkout like any clone; both paths present is for a human.
world_empty_home
git clone -q --bare "${ARI_DOTFILES_REMOTE}" "${HOME}/dotfiles"
check_repo
assert_eq "legacy path → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason legacy_path" legacy_path "$(step_get dotfiles_repo .reason)"
apply_repo
assert_eq "legacy apply exits 0" 0 "${RC}"
assert_no_file "legacy path gone" "${HOME}/dotfiles"
assert_file "renamed to the current path" "${ARI_DOTFILES_DF_GIT_DIR}/HEAD"
assert_file "renamed repo checked out" "${HOME}/.zshenv"
check_repo
assert_eq "renamed repo → ok" ok "$(step_get dotfiles_repo .status)"
git init -q --bare "${HOME}/dotfiles"
check_repo
assert_eq "both paths → fail" fail "$(step_get dotfiles_repo .status)"
assert_eq "reason legacy_conflict" legacy_conflict "$(step_get dotfiles_repo .reason)"
assert_eq "legacy_conflict is manual" true "$(step_get dotfiles_repo .manual)"
rm -rf "${HOME}/dotfiles"

# The Nix port's layout: a plain clone at ~/dotfiles, its own work tree (home-manager links its
# files into HOME). Not the pre-harness bare repo at that path; repaired and checked like the bare one.
world_empty_home
git clone -q "${ARI_DOTFILES_REMOTE}" "${HOME}/dotfiles"
bare_git_dir="${ARI_DOTFILES_DF_GIT_DIR}"
export ARI_DOTFILES_DF_GIT_DIR="${HOME}/dotfiles/.git"
apply_repo
assert_eq "clone apply exits 0" 0 "${RC}"
assert_no_file "clone: no bare repo made" "${bare_git_dir}"
assert_no_file "clone: nothing checked out into HOME" "${HOME}/.zshenv"
assert_eq "clone: hooksPath set" "${ARI_DOTFILES_DF_HOOKS}" "$(git -C "${HOME}/dotfiles" config --local --get core.hooksPath)"
check_repo
assert_eq "clone → ok" ok "$(step_get dotfiles_repo .status)"
printf '\n# local edit\n' >> "${HOME}/dotfiles/.zshenv"
check_repo
assert_eq "clone: an edit in the clone → warn uncommitted" uncommitted "$(step_get dotfiles_repo .reason)"
git -C "${HOME}/dotfiles" checkout -q -- .zshenv
export ARI_DOTFILES_DF_GIT_DIR="${bare_git_dir}"
rm -rf "${HOME}/dotfiles"

world_empty_home
bump_now_secs 60
nm init --only dotfiles_repo --dry-run
if (( RC == 0 || RC == 1 )); then pass "dry-run exits by verdict (rc=${RC})"; else fail "dry-run exits by verdict" "rc=${RC}"; fi
assert_no_file "dry-run clones nothing" "${ARI_DOTFILES_DF_GIT_DIR}"
assert_contains "dry-run says what it would do" "${ERR}" "would run apply::dotfiles_repo"
assert_eq "dry-run never reaches curl" "" "$(shim_log curl)"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
