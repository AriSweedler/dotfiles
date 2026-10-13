#!/usr/bin/env bash
# `dotfiles status`: the pure helpers behind the cards (relative age, ahead/behind, push verdict),
# the plain output byte for byte in a world, and the cards path through a fake gum (its call log).
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos

# st_run [VAR=value…] -- CODE: the kernel plus cmd/status.zsh in the hermetic env, then CODE; OUT keeps every byte.
st_run() {
  local -a extra=()
  while [[ "$1" != -- ]]; do extra+=("$1"); shift; done
  shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${extra[@]}" "${FIX}/tools/zsh" -c \
    'for f in "$1"/lib/*.zsh(N); do source "${f}"; done; source "$1/cmd/status.zsh"; eval "$2"' _ "${ORIG_CONFIG_DIR}/dotfiles" "$1" \
    > "${FIX}/st.out" 2> "${FIX}/st.err" || RC=$?
  OUT="$(cat "${FIX}/st.out"; printf x)"; OUT="${OUT%x}"
  ERR="$(cat "${FIX}/st.err")"
}
one() { st_run -- "$1"; printf '%s' "${OUT%$'\n'}"; }

# ── status::age ──────────────────────────────────────────────────────────────
assert_eq "age: under a minute is just now" "just now" "$(one 'status::age 1000 1059')"
assert_eq "age: minutes" "5m ago" "$(one 'status::age 1000 1300')"
assert_eq "age: hours, floored" "3h ago" "$(one 'status::age 0 $(( 3 * 3600 + 3599 ))')"
assert_eq "age: days" "7d ago" "$(one 'status::age 0 $(( 7 * 86400 + 5 ))')"
assert_eq "age: the clock defaults to ARI_DOTFILES_NOW" "1d ago" "$(one 'status::age $(( ARI_DOTFILES_NOW - 86400 ))')"
assert_eq "age: no timestamp is ?" "?" "$(one 'status::age ""')"
assert_eq "iso_epoch: a header stamp is UTC" "1790891328" "$(one 'TZ=America/Los_Angeles status::iso_epoch 2026-10-01T21:48:48Z')"
assert_eq "iso_epoch: garbage is nothing" "" "$(one 'status::iso_epoch yesterday')"

# ── status::drift ────────────────────────────────────────────────────────────
T=$'\t'
assert_eq "drift: in sync" "ok${T}main${T}✓ in sync" "$(one 'status::drift "## main...origin/main"')"
assert_eq "drift: ahead says push" "warn${T}main${T}↑1 ahead · run dotfiles push" "$(one 'status::drift "## main...origin/main [ahead 1]"')"
assert_eq "drift: behind says pull" "warn${T}main${T}↓2 behind · run dotfiles pull" "$(one 'status::drift "## main...origin/main [behind 2]"')"
assert_eq "drift: both is diverged" "warn${T}dev${T}↑3 ↓12 diverged · run dotfiles pull" "$(one 'status::drift "## dev...origin/dev [ahead 3, behind 12]"')"
assert_eq "drift: no upstream" "warn${T}main${T}no upstream" "$(one 'status::drift "## main"')"
assert_eq "drift: a gone upstream" "warn${T}main${T}no upstream" "$(one 'status::drift "## main...origin/main [gone]"')"
assert_eq "drift: an unborn branch" "warn${T}main${T}no upstream" "$(one 'status::drift "## No commits yet on main"')"

# ── status::push_verdict ─────────────────────────────────────────────────────
assert_eq "verdict: a pushed line is ok with its ref" "ok${T}main@fde5e0d" \
  "$(one 'status::push_verdict "[INFO] [2026-10-01T14:48:51Z] [push_repo] Pushed | main@fde5e0d5 -> https://github.com/a/b.git"')"
assert_eq "verdict: [ERROR] is a failure" "fail${T}" "$(one 'status::push_verdict "[ERROR] [2026-10-01T14:48:51Z] [push_repo] rejected | remote=origin"')"
assert_eq "verdict: a ref with a slash, sha cut to 7" "ok${T}feat/x@0123456" "$(one 'status::push_verdict "[INFO] Pushed | feat/x@0123456789abcdef"')"
assert_eq "verdict: an email is not a ref" "ok${T}" "$(one 'status::push_verdict "[INFO] committed as a@example.invalid"')"

# ── The plain output in a world, byte for byte ───────────────────────────────
PUSH_DIR="${XDG_STATE_HOME}/dotfiles/push"
mkdir -p "${PUSH_DIR}"
printf '# 2026-09-01T10:00:00Z dotfiles push -> shared\n[INFO] [2026-09-01T10:00:02Z] [push_repo] Pushed | main@abcdef0123 -> origin\n' > "${PUSH_DIR}/shared.log"
printf '# 2026-09-02T10:00:00Z dotfiles push -> local\n[INFO] start\n[ERROR] [2026-09-02T10:00:03Z] [push_repo] rejected | remote=origin\n' > "${PUSH_DIR}/local.log"
nm status
assert_eq "plain: exits 0" 0 "${RC}"
assert_eq "plain: the three sections as main prints them" "tiers
  shared: ## main  uncommitted=0
  local: ## No commits yet on main  uncommitted=0
submodules (space = at the pointer, + = elsewhere, - = not initialized)
  none declared
last push (${PUSH_DIR}; 'dotfiles logs' for the whole run)
  local                      2026-09-02T10:00:00Z  [2026-09-02T10:00:03Z] [push_repo] rejected | remote=origin
  shared                     2026-09-01T10:00:00Z  [2026-09-01T10:00:02Z] [push_repo] Pushed | main@abcdef0123 -> origin" "${OUT}"

# A declared submodule: not initialized (-), then checked out at the pointer (space) and past it (+).
SUB="${FIX}/subsrc"
git init -q --initial-branch=main "${SUB}"
git -C "${SUB}" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
SUB_SHA="$(git -C "${SUB}" rev-parse HEAD)"
printf '[submodule ".config/sub"]\n\tpath = .config/sub\n\turl = %s\n' "${SUB}" > "${HOME}/.gitmodules"
df_git update-index --add --cacheinfo "160000,${SUB_SHA},.config/sub"
df_git -c core.hooksPath=/dev/null commit -q -m "add sub"
nm status
assert_contains "plain: an uninitialized submodule" "${OUT}" $'\n'"  -${SUB_SHA} .config/sub"$'\n'
git clone -q "${SUB}" "${HOME}/.config/sub"
# A clone's .git is a directory; a submodule checkout's is a file, which is what is_repo_present looks for.
mv "${HOME}/.config/sub/.git" "${FIX}/sub.git"
printf 'gitdir: %s\n' "${FIX}/sub.git" > "${HOME}/.config/sub/.git"
nm status
assert_contains "plain: at the pointer" "${OUT}" $'\n'"   ${SUB_SHA} .config/sub (heads/main)"$'\n'
git -C "${HOME}/.config/sub" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
nm status
assert_contains "plain: past the pointer" "${OUT}" $'\n'"  +$(git -C "${HOME}/.config/sub" rev-parse HEAD) .config/sub (heads/main)"$'\n'

# ── The cards, through a fake gum that logs its calls ────────────────────────
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\nprintf "GUM\\n"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
git clone -q --bare "${ARI_DOTFILES_DF_GIT_DIR}" "${FIX}/remotes/df-origin.git"
df_git remote add origin "${FIX}/remotes/df-origin.git"
df_git fetch -q origin
df_git branch -q --set-upstream-to=origin/main main
printf 'x\n' > "${HOME}/.config/card.txt"
df_git add "${HOME}/.config/card.txt"
df_git -c core.hooksPath=/dev/null commit -q -m "ahead by one"
printf 'y\n' > "${HOME}/.config/card.txt"
export ARI_DOTFILES_NOW=$(( 1788256800 + 3 * 86400 ))   # three days after the shared push header
rm -f "${FIX}/gum.log"
st_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- 'cmd_status'
GUM_LOG="$(cat "${FIX}/gum.log" 2>/dev/null)"
assert_eq "cards: exits 0" 0 "${RC}"
assert_eq "cards: what gum drew is the output" $'GUM\n' "${OUT}"
assert_eq "cards: three boxes and one join" 4 "$(grep -c . "${FIX}/gum.log")"
assert_eq "cards: the boxes are joined side by side" 1 "$(grep -c '^join --horizontal' "${FIX}/gum.log")"
assert_contains "cards: tiers card" "${GUM_LOG}" "tiers"
assert_contains "cards: shared is ahead and says push" "${GUM_LOG}" "↑1 ahead · run dotfiles push"
# The edited file and the submodule past its pointer: what plain calls uncommitted=2.
assert_contains "cards: the uncommitted count" "${GUM_LOG}" "2 uncommitted"
assert_contains "cards: the submodule's short name and branch" "${GUM_LOG}" "sub  "
assert_contains "cards: the submodule is past its pointer" "${GUM_LOG}" "+ ahead of pointer · bumped on push"
SUB_HEAD="$(git -C "${HOME}/.config/sub" rev-parse HEAD)"
assert_contains "cards: a 7-char sha, not 40" "${GUM_LOG}" "${SUB_HEAD:0:7}"
assert_not_contains "cards: no 40-char sha" "${GUM_LOG}" "${SUB_HEAD}"
assert_contains "cards: the push age" "${GUM_LOG}" "3d ago"
assert_contains "cards: the pushed ref" "${GUM_LOG}" "main@abcdef0"
assert_contains "cards: the failed push is ✗" "${GUM_LOG}" "✗"
assert_not_contains "cards: no raw porcelain" "${GUM_LOG}" "## main"

# Too narrow for three side by side: stacked, no join.
rm -f "${FIX}/gum.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\nprintf "%%060d\\n" 0\n' "${FIX}" > "${FAKE_GUM}"
st_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" COLUMNS=150 -- 'cmd_status'
assert_eq "narrow: three boxes, no join" 3 "$(grep -c . "${FIX}/gum.log")"
assert_eq "narrow: the boxes stacked" 3 "$(grep -c '^0*$' "${FIX}/st.out")"

# NO_COLOR keeps the plain path even with gum and the fancy seam.
rm -f "${FIX}/gum.log"
st_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" NO_COLOR=1 -- 'cmd_status'
assert_contains "NO_COLOR: plain sections" "${OUT}" "submodules (space = at the pointer"
assert_no_file "NO_COLOR: gum never called" "${FIX}/gum.log"

report
