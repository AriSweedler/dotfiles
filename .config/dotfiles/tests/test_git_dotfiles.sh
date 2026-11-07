#!/usr/bin/env bash
# git/bin/git-dotfiles, the `git df` alias: the bare repo with HOME as its work tree until a
# plain clone exists at ~/dotfiles, then the clone; a HOME path linked into the clone is added
# by its clone path; a relative path is the caller's, from a subdirectory too.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
GD="${ORIG_CONFIG_DIR}/git/bin/git-dotfiles"
# Through git, as the alias runs it: git sets GIT_PREFIX and runs it from the repo top.
gdf() { git -c core.hooksPath=/dev/null -c alias.df="!\"${GD}\"" df "$@"; }

mkdir -p "${HOME}/.config/zsh"
printf 'one\n' > "${HOME}/.config/zsh/a.zsh"
git init -q --bare --initial-branch=main "${HOME}/dotfiles.git"
git --git-dir="${HOME}/dotfiles.git" --work-tree="${HOME}" add "${HOME}/.config/zsh/a.zsh"
git --git-dir="${HOME}/dotfiles.git" --work-tree="${HOME}" -c user.name=t -c user.email=t@example.com commit -q -m seed

# ── no clone: the bare repo, HOME its work tree ──
assert_eq "bare: lists HOME's tracked file" ".config/zsh/a.zsh" "$(cd "${HOME}" && gdf ls-files)"
printf 'two\n' >> "${HOME}/.config/zsh/a.zsh"
assert_eq "bare: an edit in HOME is dirty" " M .config/zsh/a.zsh" "$(cd "${HOME}" && gdf status --short -uno)"
git --git-dir="${HOME}/dotfiles.git" --work-tree="${HOME}" checkout -q -- .config/zsh/a.zsh

# ── a clone at ~/dotfiles: the clone; HOME's file is a link into it ──
git clone -q "${HOME}/dotfiles.git" "${HOME}/dotfiles"
rm "${HOME}/.config/zsh/a.zsh"
ln -s "${HOME}/dotfiles/.config/zsh/a.zsh" "${HOME}/.config/zsh/a.zsh"
printf 'three\n' >> "${HOME}/.config/zsh/a.zsh"
assert_eq "clone: the edit through the link is the clone's" " M .config/zsh/a.zsh" "$(cd /tmp && gdf status --short)"
(cd /tmp && gdf add "${HOME}/.config/zsh/a.zsh")
assert_eq "clone: add by the HOME path stages the clone's file" "M  .config/zsh/a.zsh" "$(cd /tmp && gdf status --short)"
assert_eq "clone: a relative path from a subdirectory" ".config/zsh/a.zsh" "$(cd "${HOME}/dotfiles/.config" && gdf diff --cached --name-only -- zsh)"
(cd /tmp && PATH="${PATH}:/usr/bin:/bin" gdf submodule status > /dev/null)   # git-submodule is a sh script: it needs sed
assert_eq "clone: submodule runs from outside the clone" 0 "$?"
assert_eq "clone: the bare repo is left alone" "" "$(git --git-dir="${HOME}/dotfiles.git" --work-tree="${HOME}" diff --cached --name-only)"

report
