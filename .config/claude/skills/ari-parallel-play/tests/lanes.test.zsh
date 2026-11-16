#!/usr/bin/env zsh
# Automated tests for bin/worktree.zsh and bin/lane-overlap.zsh against throwaway repos: no network.
# worktree: a dry run changes nothing; open makes the branch from the base, is idempotent, checks out an
# existing branch, refuses a directory holding another lane's branch, links the shared directory and
# refuses to replace a real one; handoff refuses a dirty tree (changes inside the link aside) and a
# submodule commit no remote holds, unlinks, removes the worktree and keeps the branch, and is a no-op
# once the worktree is gone.
# lane-overlap: owned files are the lane's commits, working-tree changes and untracked files, the ignored
# prefix dropped; overlaps are pairwise; a lane overlapping a running lane is not ready; a handed-off
# lane is measured from origin/<branch>; an empty lane is [] and not a crash.
# Run: zsh tests/lanes.test.zsh (from the skill dir, or by path)
set -uo pipefail

readonly HERE="${0:A:h}"
readonly WORKTREE="${HERE:h}/bin/worktree.zsh"
readonly OVERLAP="${HERE:h}/bin/lane-overlap.zsh"
readonly T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lanes-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "${T}"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${T}/gitconfig"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --file "${GIT_CONFIG_GLOBAL}" init.defaultBranch main
git config --file "${GIT_CONFIG_GLOBAL}" protocol.file.allow always
unset DRY_RUN

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}

typeset -g out="" err="" rc=0
run() { rc=0; out="$("$@" 2>"${T}/err")" || rc=$?; err="$(<"${T}/err")"; }
commit() { print -r -- "${3:-x}" > "${1}/${2}"; git -C "${1}" add -A; git -C "${1}" commit -q -m "${2}"; }

# A remote and its clone, the root checkout, with node_modules as the shared dependency directory.
git init -q --bare "${T}/remote.git"
git clone -q "${T}/remote.git" "${T}/root" 2>/dev/null
commit "${T}/root" README.md "readme"
mkdir -p "${T}/root/docs" "${T}/root/node_modules"; commit "${T}/root" docs/guide.md "guide"
print 'node_modules' > "${T}/root/.gitignore"; commit "${T}/root" .gitignore 'node_modules'
git -C "${T}/root" push -q origin main
R="${T}/root"

# ── worktree open ──
run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-a" --branch lane-a --link node_modules
check "open dry run: exit 0" 0 "${rc}"
check "open dry run: no worktree" "no" "$([[ -e "${T}/wt-a" ]] && print yes || print no)"
check "open dry run: no branch" "" "$(git -C "${R}" branch --list lane-a)"
contains "open dry run: says it is one" "dry_run=1" "${out}"

run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-a" --branch lane-a --link node_modules --execute
check "open: exit 0" 0 "${rc}"
check "open: the worktree is on the new branch" "lane-a" "$(git -C "${T}/wt-a" branch --show-current)"
check "open: the branch starts at the base" "$(git -C "${R}" rev-parse origin/main)" "$(git -C "${T}/wt-a" rev-parse HEAD)"
check "open: the shared directory is a symlink to the root's" "${R}/node_modules" "$(readlink "${T}/wt-a/node_modules")"

run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-a" --branch lane-a --link node_modules --execute
check "open again: exit 0" 0 "${rc}"
contains "open again: changes nothing" "changes=0" "${out}"

run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-a" --branch lane-b --execute
check "open: a directory holding another lane's branch is refused" 1 "${rc}"
contains "open: and it names both branches" "current='lane-a' expected='lane-b'" "${err}"

git -C "${R}" branch -q existing origin/main
run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-e" --branch existing --execute
check "open: an existing branch is checked out, not recreated" "existing" "$(git -C "${T}/wt-e" branch --show-current)"

mkdir -p "${T}/wt-e/node_modules"; print keep > "${T}/wt-e/node_modules/real"
run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-e" --branch existing --link node_modules --execute
check "open: a real directory at the link name is refused" 1 "${rc}"
check "open: and left as it was" "keep" "$(<"${T}/wt-e/node_modules/real")"

# ── worktree handoff ──
commit "${T}/wt-a" a.txt "a work"
print dirty >> "${T}/wt-a/a.txt"
run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-a" --link node_modules --execute
check "handoff: a dirty tree is refused" 1 "${rc}"
check "handoff: the refused worktree keeps its link" "${R}/node_modules" "$(readlink "${T}/wt-a/node_modules")"
git -C "${T}/wt-a" checkout -q -- a.txt

run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-a" --link node_modules
check "handoff dry run: the worktree stays" "yes" "$([[ -d "${T}/wt-a" ]] && print yes || print no)"

run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-a" --link node_modules --execute
check "handoff: exit 0" 0 "${rc}"
check "handoff: the worktree is gone" "no" "$([[ -e "${T}/wt-a" ]] && print yes || print no)"
check "handoff: the branch and its commit stay" "a.txt" "$(git -C "${R}" log -1 --format=%s lane-a)"
check "handoff: the root's shared directory is untouched" "yes" "$([[ -d "${R}/node_modules" && ! -L "${R}/node_modules" ]] && print yes || print no)"

run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-a" --execute
check "handoff: a worktree already gone is exit 0" 0 "${rc}"

run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-e" --link node_modules --execute
check "handoff: a real directory at the link name is refused" 1 "${rc}"
check "handoff: and the worktree stays" "yes" "$([[ -d "${T}/wt-e" ]] && print yes || print no)"

# A submodule commit no remote holds would be lost with the worktree's modules dir.
git init -q --bare "${T}/sub.git"
git clone -q "${T}/sub.git" "${T}/sub" 2>/dev/null; commit "${T}/sub" s.txt "s1"; git -C "${T}/sub" push -q origin main
git -C "${R}" submodule add -q "${T}/sub.git" vendor/sub 2>/dev/null
git -C "${R}" commit -q -m "add submodule"; git -C "${R}" push -q origin main
zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/wt-s" --branch lane-s --base main --execute >/dev/null 2>&1
git -C "${T}/wt-s" submodule update -q --init 2>/dev/null
git -C "${T}/wt-s/vendor/sub" switch -q -c local-only
commit "${T}/wt-s/vendor/sub" s2.txt "unpushed"
git -C "${T}/wt-s" add vendor/sub; git -C "${T}/wt-s" commit -q -m "bump sub"
run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-s" --execute
check "handoff: a submodule commit on no remote branch is refused" 1 "${rc}"
contains "handoff: it names the submodule" "submodule='vendor/sub'" "${err}"
check "handoff: the unpushed submodule commit survives" "s2.txt" "$(git -C "${T}/wt-s/vendor/sub" log -1 --format=%s)"
git -C "${T}/wt-s/vendor/sub" push -q origin local-only
git -C "${T}/wt-s/vendor/sub" fetch -q origin
run zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/wt-s" --execute
check "handoff: once pushed, the submodule worktree goes" 0 "${rc}"
check "handoff: and its branch stays" "bump sub" "$(git -C "${R}" log -1 --format=%s lane-s)"

run zsh "${WORKTREE}" --action bogus --root "${R}" --dir "${T}/x"
check "usage: an invalid action is exit 1" 1 "${rc}"
run zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/x"
check "usage: open without --branch is exit 1" 1 "${rc}"

# ── lane-overlap ──
for l in one two three; do zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/lo-${l}" --branch "lo-${l}" --link node_modules --execute >/dev/null 2>&1; done
commit "${T}/lo-one" shared.txt "one"              # committed
print change >> "${T}/lo-two/shared.txt" 2>/dev/null || print change > "${T}/lo-two/shared.txt"   # untracked in two
print doc >> "${T}/lo-two/docs/guide.md"           # a working-tree change under the shared prefix
print solo > "${T}/lo-three/solo.txt"
print junk > "${T}/root/node_modules/pkg.js"       # inside the link: never owned
result() { print -r -- "${out}" | sed -n '/=== start RESULT ===/{n;p;}'; }

run zsh "${OVERLAP}" --root "${R}" --lane "one=${T}/lo-one" --lane "two=${T}/lo-two" --lane "three=${T}/lo-three" --running one
check "overlap: exit 0" 0 "${rc}"
check "overlap: lane one owns its committed file" '["shared.txt"]' "$(result | jq -c '.lanes[] | select(.id=="one") | .files_owned')"
check "overlap: lane two owns its change and its untracked file, not the linked dir" '["docs/guide.md","shared.txt"]' "$(result | jq -c '.lanes[] | select(.id=="two") | .files_owned')"
check "overlap: the docs/ change is a shared file" '["docs/guide.md"]' "$(result | jq -c '.lanes[] | select(.id=="two") | .shared_files')"
check "overlap: one and two overlap on the file both touch" '[{"a":"one","b":"two","files":["shared.txt"]}]' "$(result | jq -c '.overlaps')"
check "overlap: with one running, only three is ready" '["three"]' "$(result | jq -c '.ready')"

run zsh "${OVERLAP}" --root "${R}" --lane "one=${T}/lo-one" --lane "three=${T}/lo-three"
check "overlap: nothing running, disjoint lanes are both ready" '["one","three"]' "$(result | jq -c '.ready')"

git -C "${T}/lo-one" push -q origin lo-one
zsh "${WORKTREE}" --action handoff --root "${R}" --dir "${T}/lo-one" --link node_modules --execute >/dev/null 2>&1
run zsh "${OVERLAP}" --root "${R}" --lane "one=lo-one" --lane "two=${T}/lo-two" --running two
check "overlap: a handed-off lane is measured from origin/<branch>" '["shared.txt"]' "$(result | jq -c '.lanes[] | select(.id=="one") | .files_owned')"
check "overlap: and still blocked by the running lane it overlaps" '[]' "$(result | jq -c '.ready')"

zsh "${WORKTREE}" --action open --root "${R}" --dir "${T}/lo-empty" --branch lo-empty --execute >/dev/null 2>&1
run zsh "${OVERLAP}" --root "${R}" --lane "empty=${T}/lo-empty"
check "overlap: an empty lane is exit 0" 0 "${rc}"
check "overlap: and owns nothing" '[]' "$(result | jq -c '.lanes[0].files_owned')"

run zsh "${OVERLAP}" --root "${R}" --lane "ghost=no-such-branch"
check "overlap: a source that is neither a worktree nor a remote branch is exit 1" 1 "${rc}"
run zsh "${OVERLAP}" --root "${R}" --lane "one=${T}/lo-two" --running nobody
check "overlap: a running id with no lane is exit 1" 1 "${rc}"

print -- "lanes.test: ${pass} passed, ${fail} failed"
(( fail == 0 ))
