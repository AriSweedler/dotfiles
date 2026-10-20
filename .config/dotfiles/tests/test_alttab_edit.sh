#!/usr/bin/env bash
# `alttab edit`: the patched source in alttab-free-build's clone opened in $EDITOR; on save
# free.patch becomes its header plus the clone's `git diff HEAD`, checked (applies to a clean ref,
# header names every file) before it replaces free.patch and is committed. `--header` edits
# free.patch itself. The clone is a tiny local repo; the editors are scripts; the real
# alttab-free-build does the regenerating and checking.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
ALTTAB="${HOME}/.config/alttab"
PATCH="${ALTTAB}/free.patch"
CACHE="${XDG_CACHE_HOME}/alttab-free"
SRC="${CACHE}/src"
PENDING="${CACHE}/free.patch.edit"
mkdir -p "${ALTTAB}/bin" "${HOME}/.claude/skills/ari-skill-shellscripts/lib"
cp "${ORIG_CONFIG_DIR}/alttab/bin/alttab-free-build" "${ALTTAB}/bin/"
cp "${ORIG_CONFIG_DIR}/claude/skills/ari-skill-shellscripts/lib/logging.zsh" "${HOME}/.claude/skills/ari-skill-shellscripts/lib/"
cp "${ORIG_CONFIG_DIR}/zsh/plugins/swift_cache.zsh" "${HOME}/.config/zsh/plugins/"

# Upstream: three files at v1.0.0, one more commit at v1.1.0. The clone is the build's.
UP="${FIX}/upstream"
git init -q "${UP}"
mkdir -p "${UP}/src/pro"
printf 'let a = 1\nlet b = 2\nlet c = 3\n' > "${UP}/src/App.swift"
printf 'menu one\nmenu two\nmenu three\n' > "${UP}/src/Menubar.swift"
printf 'trial on\nupsell on\n' > "${UP}/src/pro/License.swift"
git -C "${UP}" add -A && git -C "${UP}" commit -q -m one && git -C "${UP}" tag v1.0.0
printf 'later\n' > "${UP}/NEWS" && git -C "${UP}" add -A && git -C "${UP}" commit -q -m two && git -C "${UP}" tag v1.1.0
git clone -q "${UP}" "${SRC}"
git -C "${SRC}" -c advice.detachedHead=false checkout -q --detach v1.0.0

# free.patch: a header naming App and Menubar, and the diff that changes them.
printf 'let a = 1\nlet b = 20\nlet c = 3\n' > "${SRC}/src/App.swift"
printf 'menu one\nmenu three\n' > "${SRC}/src/Menubar.swift"
{
  printf 'Test patch\n==========\n\nBase: lwouis/alt-tab-macos tag v1.0.0 (https://github.com/lwouis/alt-tab-macos)\n\n'
  printf 'What it changes\n  App       b is twenty\n  Menubar   no second item\n\n'
  git -C "${SRC}" diff HEAD
} > "${PATCH}"
printf 'v1.0.0\n' > "${PATCH}.ref"
chmod 600 "${PATCH}"
seed_fake_repos

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME BODY: a /bin/sh editor; "$@" are the files it was given.
editor() { printf '#!/bin/sh\n%s\n' "$2" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
# awk_editor NAME AWK: rewrites the one file it is given with AWK.
awk_editor() { editor "$1" "awk '$2' \"\$1\" > \"\$1.tmp\" && mv \"\$1.tmp\" \"\$1\""; }
editor noop 'printf "%s\n" "$@" > '"${FIX}/opened"
editor fails 'exit 3'
editor app 'for f; do case "$f" in */App.swift) printf "let d = 4\n" >> "$f" ;; esac; done'
editor license "printf 'trial off\nupsell on\n' > ${SRC}/src/pro/License.swift"
editor untracked "printf 'new\n' > ${SRC}/src/New.swift"
awk_editor name_license '/^  Menubar/ { print; print "  License   no trial"; next } { print }'
awk_editor reword '/^  App / { print "  App       b is twenty, said differently"; next } { print }'
awk_editor body_d '/^\+let d = 4$/ { print "+let d = 40"; next } { print }'
awk_editor break_context '/^ let c = 3$/ { print " let c = 33"; next } { print }'

# edit EDITOR ARGS...: `dotfiles alttab ARGS` with that editor, no terminal.
edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" alttab "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
df_count() { df_git rev-list --count HEAD; }
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
snap() { cp "${PATCH}" "${FIX}/patch.before"; BEFORE_COUNT="$(df_count)"; }
unchanged() {
  assert_eq "$1: free.patch unchanged" "same" "$(cmp -s "${PATCH}" "${FIX}/patch.before" && echo same || echo changed)"
  assert_eq "$1: nothing committed" "${BEFORE_COUNT}" "$(df_count)"
}

# ── help and usage ──
nm help alttab
assert_contains "help lists edit" "${OUT}" "alttab edit [--header] [--no-commit]"
assert_contains "help lists --edit" "${OUT}" "--edit       the other spelling of edit"
assert_contains "help lists --header" "${OUT}" "--header     edit: open free.patch itself"
assert_contains "help lists --no-commit" "${OUT}" "--no-commit  edit: put free.patch in place"
edit noop edit --bogus
assert_eq "an unknown flag is a usage error" 64 "${RC}"

# ── no change: the patched files open, AGENTS.md's rule is said, nothing is written ──
snap
edit noop edit
assert_eq "no change: exit 0" 0 "${RC}"
assert_contains "no change: says so" "${OUT}" "alttab: no change"
assert_contains "the rule is said when the files open" "${OUT}" "keeps Pro locked except shortcut slot 2"
assert_eq "the editor gets the patched files, in the clone" "${SRC}/src/App.swift ${SRC}/src/Menubar.swift" "$(tr '\n' ' ' < "${FIX}/opened" | awk '{$1=$1; print}')"
assert_no_file "no change: no pending edit left" "${PENDING}"
unchanged "no change"
edit noop --edit
assert_eq "--edit is the other spelling" 0 "${RC}"
assert_contains "--edit: no change" "${OUT}" "alttab: no change"

# ── a source edit: free.patch is header + git diff HEAD, mode kept, committed ──
snap
edit app edit
assert_eq "source edit: exit 0" 0 "${RC}"
assert_contains "source edit: the new line is in the patch" "$(cat "${PATCH}")" "+let d = 4"
assert_eq "source edit: the header is kept" "Test patch" "$(head -n 1 "${PATCH}")"
assert_eq "source edit: the body is the clone's diff" "$(git -C "${SRC}" diff HEAD)" "$(awk '/^diff --git/ { p = 1 } p' "${PATCH}")"
assert_eq "source edit: mode 600 kept" 600 "$(perm "${PATCH}")"
assert_eq "source edit: one shared-tier commit" "$(( BEFORE_COUNT + 1 ))" "$(df_count)"
assert_eq "source edit: the subject" "dotfiles: edit alttab free.patch" "$(df_git log -1 --format=%s)"
assert_contains "source edit: the next step" "${OUT}" "next: dotfiles alttab install"
assert_no_file "source edit: no pending edit left" "${PENDING}"

# ── a file the header does not name: kept, not saved; --header resumes it ──
snap
edit license edit
assert_eq "undocumented file: exit 1" 1 "${RC}"
assert_contains "undocumented file: names it" "${ERR}" "does not name License"
assert_contains "undocumented file: the fix is --header" "${ERR}" "fix='dotfiles alttab edit --header'"
assert_file "undocumented file: the edit is kept" "${PENDING}"
unchanged "undocumented file"
edit name_license edit --header
assert_eq "header names it: exit 0" 0 "${RC}"
assert_contains "header edit: the diff is shown" "${OUT}" "+  License   no trial"
assert_contains "header edit: the License change is in the patch" "$(cat "${PATCH}")" "+trial off"
assert_contains "header edit: the header names License" "$(cat "${PATCH}")" "  License   no trial"
assert_eq "header edit: committed" "$(( BEFORE_COUNT + 1 ))" "$(df_count)"
assert_no_file "header edit: no pending edit left" "${PENDING}"
assert_no_file "header edit: no base hash left" "${PENDING}.base"

# ── --header: a reworded line, then a change to the diff itself the clone follows ──
edit reword edit --header --no-commit
assert_eq "reword: exit 0" 0 "${RC}"
assert_contains "reword: before and after" "${OUT}" "-  App       b is twenty"
assert_contains "--no-commit: says so" "${OUT}" "not committed"
edit body_d edit --header --no-commit
assert_eq "body change in --header: exit 0" 0 "${RC}"
assert_contains "body change in --header: the clone follows free.patch" "$(cat "${SRC}/src/App.swift")" "let d = 40"
assert_eq "body change in --header: the clone's diff is the body again" "$(git -C "${SRC}" diff HEAD)" "$(awk '/^diff --git/ { p = 1 } p' "${PATCH}")"

# ── a --header edit that breaks the patch: kept; a newer free.patch sets it aside ──
snap
edit break_context edit --header
assert_eq "broken patch: exit 1" 1 "${RC}"
assert_contains "broken patch: says it does not apply" "${ERR}" "does not apply to a clean v1.0.0"
assert_contains "broken patch: resume with --header" "${ERR}" "fix='dotfiles alttab edit --header'"
assert_file "broken patch: kept" "${PENDING}"
unchanged "broken patch"
printf '\n' >> "${PATCH}"
edit noop edit --header
assert_eq "stale pending edit: exit 0" 0 "${RC}"
assert_contains "stale pending edit: set aside" "${ERR}" "made against an older free.patch; set aside"
assert_file "stale pending edit: kept as .stale" "${PENDING}.stale"
cp "${FIX}/patch.before" "${PATCH}"

# ── the editor fails: nothing written ──
snap
edit fails edit
assert_eq "editor fails: exit 1" 1 "${RC}"
assert_contains "editor fails: says so" "${ERR}" "editor exited non-zero"
unchanged "editor fails"

# ── a new file is not in the patch: said, and it is no change ──
edit untracked edit
assert_eq "new file only: exit 0" 0 "${RC}"
assert_contains "new file only: warns it is not in the patch" "${ERR}" "new files are not in the patch until git knows them | files='src/New.swift'"
rm -f "${SRC}/src/New.swift"

# ── refusals ──
snap
mkdir -p "${CACHE}/rebase" && : > "${CACHE}/rebase/.free-rebase-target"
edit noop edit
assert_eq "rebase in progress: exit 1" 1 "${RC}"
assert_contains "rebase in progress: finish it" "${ERR}" "fix='alttab-free-build --finish-patch'"
rm -rf "${CACHE}/rebase"

git -C "${SRC}" stash -q && git -C "${SRC}" -c advice.detachedHead=false checkout -q --detach v1.1.0
edit noop edit
assert_eq "clone at another ref: exit 1" 1 "${RC}"
assert_contains "clone at another ref: rebuild" "${ERR}" "not at free.patch's ref"
assert_contains "clone at another ref: the fix" "${ERR}" "fix='alttab-free-build --build-only'"
git -C "${SRC}" -c advice.detachedHead=false checkout -q --detach v1.0.0

edit noop edit
assert_eq "clone without the patch: applied, exit 0" 0 "${RC}"
assert_contains "clone without the patch: says so" "${ERR}" "applying free.patch to the clone"
assert_eq "clone without the patch: now carries it" "$(git -C "${SRC}" diff HEAD)" "$(awk '/^diff --git/ { p = 1 } p' "${PATCH}")"
git -C "${SRC}" stash drop -q

printf 'stray\n' >> "${SRC}/src/Menubar.swift"
edit noop edit
assert_eq "clone with foreign changes: exit 1" 1 "${RC}"
assert_contains "clone with foreign changes: refused" "${ERR}" "the clone carries changes free.patch does not"
git -C "${SRC}" checkout -q -- src/Menubar.swift
git -C "${SRC}" apply "${PATCH}" 2>/dev/null || true

mv "${SRC}" "${SRC}.away"
edit noop edit
assert_eq "no clone: exit 1" 1 "${RC}"
assert_contains "no clone: build it" "${ERR}" "fix='alttab-free-build --build-only'"
mv "${SRC}.away" "${SRC}"
unchanged "refusals"

# ── alttab-free-build --regen-patch refuses a clone at another ref ──
build() { RC=0; env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ALTTAB}/bin/alttab-free-build" "$@" > "${FIX}/b.out" 2> "${FIX}/b.err" || RC=$?; ERR="$(cat "${FIX}/b.err")"; }
build --check-patch
assert_eq "--check-patch: the patch applies" 0 "${RC}"
assert_contains "--check-patch: says so" "${ERR}" "Patch applies to a clean v1.0.0"
assert_eq "--check-patch: its worktree is gone" "1" "$(git -C "${SRC}" worktree list | wc -l | tr -d ' ')"
build --regen-patch --ref v1.1.0
assert_eq "--regen-patch at another ref: exit 1" 1 "${RC}"
assert_contains "--regen-patch at another ref: says so" "${ERR}" "The clone is not at the patch's ref"

report
