#!/usr/bin/env bash
# git-kit: the scripts that delete branches and refs and rewrite object stores, against throwaway
# repos in a fake HOME, with a fake `gh` that answers from a table of PRs.
#
# - git-delete-if-merged-one deletes only a stale branch: a merged PR's, or a closed PR's whose every
#   commit a remote holds. It keeps a branch with no PR, an open PR, or a closed PR with commits that
#   were never pushed, and never deletes the branch checked out.
# - git-delete-if-merged-all applies that to every branch matching a pattern and leaves the rest.
# - git-dedupe-case-refs deletes remote-tracking refs that collide by case, and only those.
# - git-ready switches to the branch named after the directory and resets it onto origin/main.
# - git-health ticks a repo into one pack with a multi-pack-index, removes only tmp_pack files older
#   than two days, registers and unregisters through its registry, skips a registered repo that is
#   gone, and changes nothing under --dry-run.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
BIN="${ORIG_CONFIG_DIR}/bin"
export ARI_ZSHLIB="${ORIG_CONFIG_DIR}/zsh/plugins"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${FIX}/gitconfig" GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --file "${GIT_CONFIG_GLOBAL}" init.defaultBranch main
git config --file "${GIT_CONFIG_GLOBAL}" advice.detachedHead false

# The fake gh: `gh pr list --head BRANCH ... -q FILTER` prints "<number> <state>" for BRANCH from
# ${FIX}/prs (lines "branch number state"), filtered to MERGED and CLOSED as the jq filter does.
# `gh auth status` succeeds. Every call is logged.
SHIMS="${FIX}/git-kit-shims"
mkdir -p "${SHIMS}"
cat > "${SHIMS}/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${FIX}/gh.log"
[[ "\$1 \$2" == "auth status" ]] && exit 0
head=""
while (( \$# )); do [[ "\$1" == --head ]] && head="\$2"; shift; done
awk -v b="\${head}" '\$1 == b && (\$3 == "MERGED" || \$3 == "CLOSED") { print \$2, \$3 }' "${FIX}/prs" 2>/dev/null
EOF
cat > "${SHIMS}/repo" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "${SHIMS}/git-f" <<'EOF'
#!/bin/sh
exec git fetch --prune --quiet "$@"
EOF
chmod +x "${SHIMS}"/*
export PATH="${SHIMS}:${BIN}:${PATH}"
: > "${FIX}/prs"

words() { local w; w="$(tr '\n' ' ')"; printf '%s' "${w% }"; }
run() { RC=0; OUT="$("$@" 2>"${FIX}/err")" || RC=$?; ERR="$(cat "${FIX}/err")"; }
branches() { git -C "$1" branch --format='%(refname:short)' | LC_ALL=C sort | words; }
commit() { local repo="$1" msg="$2"; echo "${msg}" > "${repo}/${msg// /_}"; git -C "${repo}" add -A; git -C "${repo}" commit -q -m "${msg}"; }

# A remote with main, and a clone of it with branches:
#   merged-pushed   pushed, PR merged          -> deleted
#   merged-local    never pushed, PR merged    -> deleted (a squash merge leaves the local commits behind)
#   closed-pushed   pushed, PR closed          -> deleted (a remote still has every commit)
#   closed-local    a commit never pushed, PR closed -> kept: the commit exists nowhere else
#   open            PR open                    -> kept
#   nopr            no PR                      -> kept
new_clone() {
  local name="$1"
  rm -rf "${FIX:?}/${name}" "${FIX:?}/${name}.remote"
  git init -q --bare "${FIX}/${name}.remote"
  git clone -q "${FIX}/${name}.remote" "${FIX}/${name}" 2>/dev/null
  commit "${FIX}/${name}" "base"
  git -C "${FIX}/${name}" push -q origin main
  local b
  for b in merged-pushed closed-pushed; do
    git -C "${FIX}/${name}" switch -q -c "${b}" main; commit "${FIX}/${name}" "${b}"; git -C "${FIX}/${name}" push -q origin "${b}"
  done
  for b in merged-local closed-local open nopr; do
    git -C "${FIX}/${name}" switch -q -c "${b}" main; commit "${FIX}/${name}" "${b}"
  done
  git -C "${FIX}/${name}" switch -q main
}
cat > "${FIX}/prs" <<'EOF'
merged-pushed 11 MERGED
merged-local 12 MERGED
closed-pushed 13 CLOSED
closed-local 14 CLOSED
open 15 OPEN
EOF

# ── git-delete-if-merged-one ──
new_clone one
cd "${FIX}/one" || abort "no clone"
run git-delete-if-merged-one merged-pushed
assert_eq "one: a merged PR's pushed branch is deleted (exit)" 0 "${RC}"
run git-delete-if-merged-one merged-local
assert_eq "one: a merged PR's unpushed branch is deleted (squash merge)" 0 "${RC}"
run git-delete-if-merged-one closed-pushed
assert_eq "one: a closed PR's branch a remote fully holds is deleted" 0 "${RC}"
run git-delete-if-merged-one closed-local
assert_eq "one: a closed PR's branch with an unpushed commit is kept (exit 1)" 1 "${RC}"
assert_contains "one: it says why it kept it" "${ERR}" "commits no remote holds; kept | branch='closed-local'"
run git-delete-if-merged-one open
assert_eq "one: an open PR's branch is kept" 1 "${RC}"
run git-delete-if-merged-one nopr
assert_eq "one: a branch with no PR is kept" 1 "${RC}"
assert_contains "one: it says there is no merged or closed PR" "${ERR}" "No merged/closed PR found | branch='nopr'"
assert_eq "one: exactly the three stale branches are gone" "closed-local main nopr open" "$(branches "${FIX}/one")"
assert_eq "one: the kept unpushed commit is still reachable" "closed-local" "$(git -C "${FIX}/one" log -1 --format=%s closed-local)"

echo "merged-current 16 MERGED" >> "${FIX}/prs"
git -C "${FIX}/one" switch -q -c merged-current main
run git-delete-if-merged-one
assert_eq "one: the checked-out branch is never deleted, merged or not" 1 "${RC}"
assert_eq "one: it is still there" "merged-current" "$(git -C "${FIX}/one" branch --show-current)"
git -C "${FIX}/one" switch -q main
git -C "${FIX}/one" switch -q --detach main
run git-delete-if-merged-one
assert_eq "one: detached HEAD and no branch named is an error" 1 "${RC}"
assert_contains "one: it says so" "${ERR}" "not on any branch"
git -C "${FIX}/one" switch -q main

# ── git-delete-if-merged-all ──
new_clone all
cd "${FIX}/all" || abort "no clone"
git -C "${FIX}/all" switch -q -c keep/merged-elsewhere main; commit "${FIX}/all" "elsewhere"; git -C "${FIX}/all" switch -q main
echo "keep/merged-elsewhere 17 MERGED" >> "${FIX}/prs"
run git-delete-if-merged-all '^[mco]'
shopt -s extglob; OUT="${OUT//$'\e'[\[]+([0-9;])m/}"
assert_eq "all: exit 0" 0 "${RC}"
assert_eq "all: only the stale branches matching the pattern go" "closed-local keep/merged-elsewhere main nopr open" "$(branches "${FIX}/all")"
assert_contains "all: lists each deletion" "${OUT}" "deleted merged-pushed"
assert_contains "all: lists each kept branch" "${OUT}" "kept closed-local"
assert_not_contains "all: never touches a branch outside the pattern" "${OUT}" "merged-elsewhere"
assert_contains "all: counts what is left" "${ERR}" "Branches left | count='"
run git-delete-if-merged-all '^nothing-matches'
assert_eq "all: no match is exit 0" 0 "${RC}"
assert_contains "all: and says so" "${ERR}" "No branches matching '^nothing-matches'"

# ── git-dedupe-case-refs ──
rm -rf "${FIX}/case"; git init -q "${FIX}/case"; commit "${FIX}/case" "c"
sha="$(git -C "${FIX}/case" rev-parse HEAD)"
git -C "${FIX}/case" update-ref refs/remotes/origin/Feature/x "${sha}"
git -C "${FIX}/case" pack-refs --all                       # one casing packed, the other loose: both can exist on APFS
git -C "${FIX}/case" update-ref refs/remotes/origin/feature/x "${sha}" 2>/dev/null \
  || printf '%s refs/remotes/origin/feature/x\n' "${sha}" >> "${FIX}/case/.git/packed-refs"
git -C "${FIX}/case" update-ref refs/remotes/origin/unique "${sha}"
git -C "${FIX}/case" update-ref refs/heads/Local "${sha}"
cd "${FIX}/case" || abort "no repo"
run git-dedupe-case-refs
assert_eq "dedupe: exit 0" 0 "${RC}"
remotes="$(git -C "${FIX}/case" for-each-ref --format='%(refname)' refs/remotes/ | words)"
assert_eq "dedupe: both members of the colliding pair go, the unique ref stays" "refs/remotes/origin/unique" "${remotes}"
assert_eq "dedupe: local branches are never touched" "Local main" "$(branches "${FIX}/case")"
run git-dedupe-case-refs
assert_eq "dedupe: a clean repo is a quiet exit 0" "0:" "${RC}:${ERR}"

# ── git-ready ──
rm -rf "${FIX}/ready.remote" "${FIX}/work"
git init -q --bare "${FIX}/ready.remote"
git clone -q "${FIX}/ready.remote" "${FIX}/seed" 2>/dev/null; commit "${FIX}/seed" "first"; git -C "${FIX}/seed" push -q origin main
git clone -q "${FIX}/ready.remote" "${FIX}/work" 2>/dev/null
git -C "${FIX}/work" switch -q -c work; commit "${FIX}/work" "stale local work"
commit "${FIX}/seed" "second"; git -C "${FIX}/seed" push -q origin main
cd "${FIX}/work" || abort "no clone"
RETRIES=1 run git-ready
assert_eq "ready: exit 0" 0 "${RC}"
assert_eq "ready: on the branch named after the directory" "work" "$(git -C "${FIX}/work" branch --show-current)"
assert_eq "ready: reset onto the fetched origin/main" "$(git -C "${FIX}/seed" rev-parse HEAD)" "$(git -C "${FIX}/work" rev-parse HEAD)"

# ── git-health ──
REG="${XDG_STATE_HOME}/git-health/repos"
rm -rf "${FIX}/h"; git init -q "${FIX}/h"
for i in 1 2 3; do commit "${FIX}/h" "h${i}"; done
git -C "${FIX}/h" update-ref refs/prefetch/remotes/origin/main HEAD
cd "${FIX}/h" || abort "no repo"

run git-health --register --dry-run
assert_eq "health: register --dry-run exit 0" 0 "${RC}"
assert_no_file "health: register --dry-run writes no registry" "${REG}"
assert_eq "health: register --dry-run leaves gc.auto unset" "" "$(git -C "${FIX}/h" config --local gc.auto || true)"
assert_eq "health: register --dry-run keeps the prefetch ref" "1" "$(git -C "${FIX}/h" for-each-ref refs/prefetch | wc -l | tr -d ' ')"

run git-health --register
assert_eq "health: register exit 0" 0 "${RC}"
assert_eq "health: the repo is in the registry once" "${FIX}/h" "$(cat "${REG}")"
assert_eq "health: gc.auto pinned to 0" 0 "$(git -C "${FIX}/h" config --local gc.auto)"
assert_eq "health: maintenance.auto pinned to false" false "$(git -C "${FIX}/h" config --local maintenance.auto)"
assert_eq "health: prefetch refs deleted" 0 "$(git -C "${FIX}/h" for-each-ref refs/prefetch | wc -l | tr -d ' ')"
assert_eq "health: commits untouched" 3 "$(git -C "${FIX}/h" rev-list --count HEAD)"
run git-health --register
assert_eq "health: registering twice keeps one line" 1 "$(wc -l < "${REG}" | tr -d ' ')"

loose_before="$(git -C "${FIX}/h" count-objects | cut -d' ' -f1)"
run git-health --dry-run
assert_eq "health: tick --dry-run makes no pack" 0 "$(find "${FIX}/h/.git/objects/pack" -name '*.pack' | wc -l | tr -d ' ')"
assert_eq "health: tick --dry-run leaves the loose objects" "${loose_before}" "$(git -C "${FIX}/h" count-objects | cut -d' ' -f1)"

run git-health
assert_eq "health: tick exit 0" 0 "${RC}"
assert_contains "health: tick reports healthy" "${OUT}" "healthy | packs='1'"
assert_file "health: tick writes the multi-pack-index" "${FIX}/h/.git/objects/pack/multi-pack-index"
assert_eq "health: no loose objects left" 0 "$(git -C "${FIX}/h" count-objects | cut -d' ' -f1)"
assert_eq "health: every commit still reads" "h3 h2 h1" "$(git -C "${FIX}/h" log --format=%s | words)"
git -C "${FIX}/h" fsck --no-progress >/dev/null 2>&1; assert_eq "health: fsck clean after the tick" 0 "$?"

old_tmp="${FIX}/h/.git/objects/pack/tmp_pack_old"; new_tmp="${FIX}/h/.git/objects/pack/tmp_pack_new"
echo x > "${old_tmp}"; echo x > "${new_tmp}"
touch -t "$(date -v-3d +%Y%m%d%H%M)" "${old_tmp}"
run git-health --dry-run
assert_file "health: --dry-run keeps a stale tmp_pack" "${old_tmp}"
run git-health
assert_eq "health: a stale tmp_pack is self-healed (exit 0)" 0 "${RC}"
assert_contains "health: it says it self-healed" "${OUT}" "self-healed"
assert_no_file "health: the tmp_pack older than two days is removed" "${old_tmp}"
assert_file "health: a fresh tmp_pack (a repack may be writing it) is kept" "${new_tmp}"
rm -f "${new_tmp}"

mkdir -p "${FIX}/gone/.git"; printf '%s\n' "${FIX}/gone" >> "${REG}"; rm -rf "${FIX}/gone"
run git-health --all
assert_eq "health: --all with a registered repo gone is exit 1" 1 "${RC}"
assert_contains "health: it names the repo to unregister" "${OUT}" "fix='git health --unregister --repo ${FIX}/gone'"
assert_contains "health: the live repo was still ticked" "${OUT}" "[h] healthy"
run git-health --unregister --repo "${FIX}/gone"
run git-health --all
assert_eq "health: --all after unregistering the gone repo is exit 0" 0 "${RC}"
run git-health --unregister
assert_eq "health: unregister empties the registry" "" "$(cat "${REG}")"
run git-health --all
assert_eq "health: --all with an empty registry is exit 0" 0 "${RC}"
assert_contains "health: and names the fix" "${ERR}" "fix='git health --register'"

cd "${FIX}" || abort "no fix dir"
run git-health
assert_eq "health: outside a repo is exit 1" 1 "${RC}"
run git-health --bogus
assert_eq "health: an unknown flag is exit 1" 1 "${RC}"

report
