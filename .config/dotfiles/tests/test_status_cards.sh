#!/usr/bin/env bash
# `dotfiles status`: the pure helpers behind the two tables (relative age, ahead/behind, push verdict,
# last push), the plain output byte for byte in a world, and the local and remote tables through a
# fake gum that logs each call and each argument, every row state and the stale push log included.
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

# ── status::sync ─────────────────────────────────────────────────────────────
assert_eq "sync: none either way" "ok${T}✓ in sync" "$(one 'status::sync 0 0')"
assert_eq "sync: ahead says push" "warn${T}↑2 ahead · run dotfiles push" "$(one 'status::sync 2 0')"
assert_eq "sync: behind says pull" "warn${T}↓4 behind · run dotfiles pull" "$(one 'status::sync 0 4')"
assert_eq "sync: both is diverged" "warn${T}↑1 ↓1 diverged · run dotfiles pull" "$(one 'status::sync 1 1')"
assert_eq "sync: - is no upstream" "warn${T}no upstream" "$(one 'status::sync -')"

# ── status::last_push (plain mode: the glyph is its name, no colour) ─────────
LP="${FIX}/lp.log"
printf '# 2026-09-01T10:00:00Z dotfiles push -> shared\n[INFO] Pushed | main@abcdef0123 -> origin\n' > "${LP}"
LPNOW=$(( 1788256800 + 4 * 60 ))
assert_eq "last_push: no log is -" "-" "$(one "status::last_push '${FIX}/none.log' abcdef0")"
assert_eq "last_push: origin at the logged sha" "ok 4m ago" "$(one "ARI_DOTFILES_NOW=${LPNOW} status::last_push '${LP}' abcdef0123456789")"
assert_eq "last_push: no origin to compare" "ok 4m ago" "$(one "ARI_DOTFILES_NOW=${LPNOW} status::last_push '${LP}'")"
assert_eq "last_push: origin moved since is not current" "ok 4m ago · was abcdef0" "$(one "ARI_DOTFILES_NOW=${LPNOW} status::last_push '${LP}' 1234567")"
printf '# 2026-09-01T10:00:00Z dotfiles push -> shared\n[ERROR] rejected | remote=origin\n' > "${LP}"
assert_eq "last_push: a failed push" "fail 4m ago" "$(one "ARI_DOTFILES_NOW=${LPNOW} status::last_push '${LP}' 1234567")"

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
last push (\$XDG_STATE_HOME/dotfiles/push; 'dotfiles logs' for the whole run)
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

# ── The two tables, through a fake gum that logs each call and its arguments ──
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "CALL %%s\\n" "$1" >> "%s/gum.log"\nprintf "%%s\\n" "$@" >> "%s/gum.args"\nprintf "GUM\\n"\n' "${FIX}" "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
# cards_run [VAR=value…]: the fancy path; CALLS is the gum call log, ROWS every argument, colour
# stripped and runs of spaces squeezed, so a row reads 'shared main 1234567 clean'.
cards_run() {
  rm -f "${FIX}/gum.log" "${FIX}/gum.args"
  st_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" COLUMNS=200 "$@" -- 'cmd_status'
  CALLS="$(cat "${FIX}/gum.log" 2>/dev/null)"
  ROWS="$(bare_args | PATH="${ORIG_PATH}" tr -s ' ')"
}
bare_args() { PATH="${ORIG_PATH}" sed $'s/\e\\[[0-9;]*m//g' "${FIX}/gum.args" 2>/dev/null; }
has_row() { assert_contains "$1" $'\n'"${ROWS}"$'\n' $'\n'"$2"$'\n'; }

# A second submodule, declared and pointed at but never initialized: an empty directory, as a clone leaves it.
mkdir -p "${HOME}/.config/sub2"
printf '[submodule ".config/sub2"]\n\tpath = .config/sub2\n\turl = %s\n' "${SUB}" >> "${HOME}/.gitmodules"
df_git add "${HOME}/.gitmodules"
df_git update-index --add --cacheinfo "160000,${SUB_SHA},.config/sub2"
df_git -c core.hooksPath=/dev/null commit -q -m "add sub2"
git clone -q --bare "${ARI_DOTFILES_DF_GIT_DIR}" "${FIX}/remotes/df-origin.git"
df_git remote add origin "${FIX}/remotes/df-origin.git"
df_git fetch -q origin
df_git branch -q --set-upstream-to=origin/main main
ORIGIN_SHA="$(df_git rev-parse origin/main)"
printf 'x\n' > "${HOME}/.config/card.txt"
df_git add "${HOME}/.config/card.txt"
df_git -c core.hooksPath=/dev/null commit -q -m "ahead by one"
printf 'y\n' > "${HOME}/.config/card.txt"
SHARED_HEAD="$(df_git rev-parse HEAD)"
SUB_HEAD="$(git -C "${HOME}/.config/sub" rev-parse HEAD)"
# The sub's last `dotfiles push` published what its origin still has; shared's logged abcdef0 is stale.
printf '# 2026-09-01T10:00:00Z dotfiles push -> .config/sub\n[INFO] [2026-09-01T10:00:02Z] [push_repo] Pushed | main@%s -> origin\n' "${SUB_SHA}" > "${PUSH_DIR}/config-sub.log"
export ARI_DOTFILES_NOW=$(( 1788256800 + 3 * 86400 ))   # three days after the shared push header

cards_run
assert_eq "cards: exits 0" 0 "${RC}"
assert_eq "cards: what gum drew is the output" $'GUM\n' "${OUT}"
assert_eq "cards: two boxes, then one join" $'CALL style\nCALL style\nCALL join' "${CALLS}"
has_row "local: its title" "local"
has_row "local: the header row" "repo branch HEAD state"
has_row "local: shared, with what plain calls uncommitted=2" "shared main ${SHARED_HEAD:0:7} 2 uncommitted"
has_row "local: an unborn tier has no HEAD and is clean" "local main - clean"
has_row "local: a submodule past its pointer" "sub main ${SUB_HEAD:0:7} + ahead of pointer · bumped on push"
has_row "local: a submodule not initialized" "sub2 - - - not initialized · run dotfiles init"
has_row "remote: its title" "remote"
has_row "remote: the header row names dotfiles push" "repo origin sync last dotfiles push"
has_row "remote: shared ahead, its log stale against origin" "shared ${ORIGIN_SHA:0:7} ↑1 ahead · run dotfiles push ✓ 3d ago · was abcdef0"
has_row "remote: no upstream, a failed push" "local - no upstream ✗ 2d ago"
has_row "remote: a submodule ahead of its origin, its log current" "sub ${SUB_SHA:0:7} ↑1 ahead · run dotfiles push ✓ 3d ago"
has_row "remote: an uninitialized submodule" "sub2 - - -"
assert_not_contains "cards: no 40-char sha" "${ROWS}" "${SUB_HEAD}"
assert_not_contains "cards: no raw porcelain" "${ROWS}" "## main"

# Back at the pointer, in sync with origin; then origin moves on, as a push from elsewhere would.
git -C "${HOME}/.config/sub" reset -q --hard "${SUB_SHA}"
cards_run
has_row "local: a submodule at its pointer" "sub main ${SUB_SHA:0:7} ✓ at pointer"
has_row "remote: a submodule in sync" "sub ${SUB_SHA:0:7} ✓ in sync ✓ 3d ago"
git -C "${SUB}" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m three
git -C "${HOME}/.config/sub" fetch -q origin
SUB_ORIGIN="$(git -C "${HOME}/.config/sub" rev-parse origin/main)"
cards_run
has_row "remote: behind says pull, the log no longer current" "sub ${SUB_ORIGIN:0:7} ↓1 behind · run dotfiles pull ✓ 3d ago · was ${SUB_SHA:0:7}"
git -C "${HOME}/.config/sub" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m four
cards_run
has_row "remote: diverged" "sub ${SUB_ORIGIN:0:7} ↑1 ↓1 diverged · run dotfiles pull ✓ 3d ago · was ${SUB_SHA:0:7}"
git -C "${HOME}/.config/sub" checkout -q --detach "${SUB_SHA}"
cards_run
has_row "local: a detached submodule" "sub detached ${SUB_SHA:0:7} ✓ at pointer"
has_row "remote: a detached submodule has no upstream" "sub - no upstream ✓ 3d ago"

# Too narrow for both side by side: stacked, no join, the wider table clipped to the screen.
cards_run COLUMNS=40
assert_eq "narrow: two boxes, no join" $'CALL style\nCALL style' "${CALLS}"
assert_eq "narrow: the boxes stacked" $'GUM\nGUM\n' "${OUT}"
assert_contains "narrow: a clipped row ends in …" "${ROWS}" "…"
assert_eq "narrow: no row wider than the screen less the box" "" \
  "$(bare_args | PATH="${ORIG_PATH}" awk '!/^(--|style$|rounded$|0 1$)/ && length($0) > 36')"

# NO_COLOR keeps the plain path even with gum and the fancy seam.
rm -f "${FIX}/gum.log"
st_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" NO_COLOR=1 -- 'cmd_status'
assert_contains "NO_COLOR: plain sections" "${OUT}" "submodules (space = at the pointer"
assert_no_file "NO_COLOR: gum never called" "${FIX}/gum.log"

report
