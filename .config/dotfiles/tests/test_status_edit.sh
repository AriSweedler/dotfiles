#!/usr/bin/env bash
# `status --edit`: the commit plan written for the uncommitted tracked paths of both tiers, edited
# by a scripted $EDITOR with no terminal: commit lines grouped by tier and message into one commit
# each, nothing pushed; bad lines reported by number with the file kept; a FILE resumed; a path
# that went clean left alone; a restore refused without a terminal; --dry-run's would-run lines.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
seed_ldf_remote
mkdir -p "${HOME}/.config/st" "${HOME}/.local/share/dotfiles/st"
for f in a b c d e; do printf '%s\n' "${f}" > "${HOME}/.config/st/${f}.txt"; done
printf 'x\n' > "${HOME}/.local/share/dotfiles/st/x.txt"
df_git add "${HOME}/.config/st"
df_git -c core.hooksPath=/dev/null commit -q -m "st files"
ldf_git add "${HOME}/.local/share/dotfiles/st/x.txt"
ldf_git -c core.hooksPath=/dev/null commit -q -m "st local"
ldf_git push -q origin main 2>/dev/null
PLAN="${XDG_STATE_HOME}/dotfiles/status-plan.dfstatus"

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# writes NAME [SHELL]: an editor that replaces the plan with ${EDITORS}/NAME.plan, then runs SHELL.
writes() { printf '#!/bin/sh\ncp "%s/%s.plan" "$1"\n%s\n' "${EDITORS}" "$1" "${2:-}" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
printf '#!/bin/sh\nexit 0\n' > "${EDITORS}/noop"; chmod +x "${EDITORS}/noop"
printf '#!/bin/sh\ncp "$1" "%s/seen.plan"\n' "${FIX}" > "${EDITORS}/peek"; chmod +x "${EDITORS}/peek"

# st EDITOR ARGS...: `dotfiles ARGS` with that editor, no terminal.
st() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
df_count() { df_git rev-list --count HEAD; }
ldf_count() { ldf_git rev-list --count HEAD; }
dirty() { df_git status --porcelain --untracked-files=no -- "$@"; }

# ── usage ──
st noop status --dry-run
assert_eq "--dry-run without --edit: 64" 64 "${RC}"
st noop status --edit one two
assert_eq "two FILEs: 64" 64 "${RC}"
st noop status --edit "${FIX}/no-such.dfstatus"
assert_eq "a missing FILE: 64" 64 "${RC}"
st noop status extra
assert_eq "a positional without --edit: 64" 64 "${RC}"

# ── nothing uncommitted: no plan ──
st noop status --edit
assert_eq "clean: exit 0" 0 "${RC}"
assert_contains "clean: says so" "${OUT}" "nothing uncommitted in the tiers"
assert_no_file "clean: no plan written" "${PLAN}"

# ── the plan as written; unchanged is no change ──
for f in a b c d e; do printf '%s changed\n' "${f}" > "${HOME}/.config/st/${f}.txt"; done
printf 'x changed\n' > "${HOME}/.local/share/dotfiles/st/x.txt"
st peek status --edit
assert_eq "unchanged plan: exit 0" 0 "${RC}"
assert_contains "unchanged plan: says so" "${OUT}" "status: no change; nothing done"
assert_file "the plan is kept under the state dir" "${PLAN}"
SEEN="$(cat "${FIX}/seen.plan")"
assert_contains "plan: line 1 names the plan type for the editor" "${SEEN%%$'\n'*}" "# dotfiles-plan: status · actions: commit | restore | skip · danger: restore · note: commit"
assert_contains "plan: a shared line" "${SEEN}" $'\nskip            shared:.config/st/a.txt\n'
assert_contains "plan: a local line, relative to ~/.local" "${SEEN}" $'\nskip            local:share/dotfiles/st/x.txt'
assert_contains "plan: the shared heading" "${SEEN}" "# ── shared (git df"
assert_contains "plan: the shared diff --stat as a comment" "${SEEN}" "# 5 files changed, 5 insertions(+), 5 deletions(-)"
assert_contains "plan: the local diff --stat as a comment" "${SEEN}" "# 1 file changed, 1 insertion(+), 1 deletion(-)"
assert_contains "plan: names the actions" "${SEEN}" "#   restore   discard the change"
assert_eq "plan: nothing committed" "" "$(df_git log -1 --format=%s | grep -v '^st files$')"

# ── bad lines: each by number, the file kept, nothing done ──
cat > "${EDITORS}/bad.plan" <<'EOF'
# a comment
frob  shared:.config/st/a.txt
commit  shared:.config/st/b.txt
commit  shared:.config/nope.txt  # ghost
skip  other:.config/st/c.txt
commit  shared:.config/st/d.txt  # fine
restore  shared:.config/st/d.txt
commit
EOF
writes bad
df_before="$(df_count)"
st bad status --edit
assert_eq "bad lines: exit 1" 1 "${RC}"
assert_contains "bad lines: an unknown action" "${ERR}" "line 2: unknown action; use commit, restore, skip"
assert_contains "bad lines: a commit with no message" "${ERR}" "line 3: 'commit' needs a note: end the line with '# …' | item='shared:.config/st/b.txt'"
assert_contains "bad lines: an untracked path" "${ERR}" "line 4: not a file the shared tier tracks | item='shared:.config/nope.txt'"
assert_contains "bad lines: an unknown tier" "${ERR}" "line 5: expected <shared|local>:<path>"
assert_contains "bad lines: a path twice" "${ERR}" "line 7: listed twice"
assert_contains "bad lines: an action alone" "${ERR}" "line 8: expected one tier:path after 'commit'"
assert_not_contains "bad lines: a good line is not named" "${ERR}" "line 6:"
assert_contains "bad lines: the resume command" "${ERR}" "fix='dotfiles status --edit ${PLAN}'"
assert_eq "bad lines: the file is kept as edited" "$(cat "${EDITORS}/bad.plan")" "$(cat "${PLAN}")"
assert_eq "bad lines: nothing committed" "${df_before}" "$(df_count)"

# ── FILE resumes: an unchanged reopen is read, not "no change"; grouping by tier and message ──
cat > "${PLAN}" <<'EOF'
commit  shared:.config/st/a.txt  # st: group one
commit  shared:.config/st/b.txt  #   st: group one
commit  shared:.config/st/c.txt  # st: solo
commit  local:share/dotfiles/st/x.txt     # st: group one
skip    shared:.config/st/d.txt  # a skip's message is ignored
EOF
df_before="$(df_count)" ldf_before="$(ldf_count)" ldf_remote="$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
st noop status --edit "${PLAN}"
assert_eq "resume: exit 0" 0 "${RC}"
assert_eq "grouping: two shared commits" "$(( df_before + 2 ))" "$(df_count)"
assert_eq "grouping: one local commit" "$(( ldf_before + 1 ))" "$(ldf_count)"
assert_eq "grouping: one tier and message is one commit" ".config/st/a.txt
.config/st/b.txt" "$(df_git show --format= --name-only HEAD~1)"
assert_eq "grouping: the message, verbatim" "st: group one" "$(df_git log -1 --format=%s HEAD~1)"
assert_eq "grouping: the second message is its own commit" ".config/st/c.txt" "$(df_git show --format= --name-only HEAD)"
assert_eq "grouping: the local commit" "st: group one" "$(ldf_git log -1 --format=%s)"
assert_eq "never pushes: the local remote is where it was" "${ldf_remote}" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
assert_contains "the skip line stays uncommitted" "$(dirty .config/st/d.txt)" "d.txt"
assert_contains "the shared tier waits for dotfiles push" "${OUT}" 'Run `dotfiles push` when ready.'
assert_contains "the tables again (plain: the tiers section)" "${OUT}" $'\ntiers\n  shared:'
assert_contains "ends with next: dotfiles push" "$(tail -n 1 "${FIX}/nm.out")" "next: dotfiles push"

# ── a restore without a terminal is refused, and nothing else runs either ──
cat > "${EDITORS}/restore.plan" <<'EOF'
commit   shared:.config/st/e.txt  # st: e
restore  shared:.config/st/d.txt
EOF
writes restore
df_before="$(df_count)"
st restore status --edit
assert_eq "restore, no terminal: exit 1" 1 "${RC}"
assert_contains "restore, no terminal: why" "${ERR}" "a restore discards changes and needs a terminal"
assert_eq "restore, no terminal: no commit either" "${df_before}" "$(df_count)"
assert_eq "restore, no terminal: the change is still there" "d changed" "$(cat "${HOME}/.config/st/d.txt")"

# ── --dry-run: the would-run lines, the restore included, and nothing changes ──
st restore status --edit --dry-run
assert_eq "dry run: exit 0" 0 "${RC}"
assert_contains "dry run: the add" "${OUT}" "would run: git --git-dir=${ARI_DOTFILES_DF_GIT_DIR} --work-tree=${HOME} add -- ${HOME}/.config/st/e.txt"
assert_contains "dry run: the commit" "${OUT}" "would run: git --git-dir=${ARI_DOTFILES_DF_GIT_DIR} --work-tree=${HOME} commit -m 'st: e'"
assert_contains "dry run: the restore" "${OUT}" "restore --source=HEAD --staged --worktree -- ${HOME}/.config/st/d.txt"
assert_contains "dry run: the box says so" "${OUT}" "(dry run)"
assert_eq "dry run: nothing committed" "${df_before}" "$(df_count)"
assert_eq "dry run: nothing restored" "d changed" "$(cat "${HOME}/.config/st/d.txt")"
assert_contains "dry run: next is the real run" "${OUT}" "next: dotfiles status --edit"
st restore --dry-run status --edit
assert_eq "dry run as a top-level flag: exit 0" 0 "${RC}"
assert_eq "dry run as a top-level flag: nothing committed" "${df_before}" "$(df_count)"

# ── a path that went clean while the plan was open is left alone; the rest still commits ──
cat > "${EDITORS}/clean.plan" <<'EOF'
commit  shared:.config/st/d.txt  # st: d and e
commit  shared:.config/st/e.txt  # st: d and e
EOF
writes clean "printf 'd\\n' > '${HOME}/.config/st/d.txt'"
st clean status --edit
assert_eq "went clean: exit 0" 0 "${RC}"
assert_contains "went clean: named" "${ERR}" "line 1: no uncommitted change now; left alone | item='shared:.config/st/d.txt'"
assert_eq "went clean: the other path is the commit" ".config/st/e.txt" "$(df_git show --format= --name-only HEAD)"

# ── staged changes in a tier refuse its commits before anything runs ──
printf 'a again\n' > "${HOME}/.config/st/a.txt"
printf 'b again\n' > "${HOME}/.config/st/b.txt"
df_git add "${HOME}/.config/st/a.txt"
cat > "${EDITORS}/staged.plan" <<'EOF'
commit  shared:.config/st/b.txt  # st: b
EOF
writes staged
df_before="$(df_count)"
st staged status --edit
assert_eq "staged: exit 1" 1 "${RC}"
assert_contains "staged: why" "${ERR}" "the shared tier has staged changes"
assert_eq "staged: nothing committed" "${df_before}" "$(df_count)"
df_git restore --staged "${HOME}/.config/st/a.txt"

# ── every line left skip (a comment added) does nothing ──
cat > "${EDITORS}/skips.plan" <<'EOF'
# just looking
skip  shared:.config/st/a.txt
EOF
writes skips
st skips status --edit
assert_eq "all skip: exit 0" 0 "${RC}"
assert_contains "all skip: says so" "${OUT}" "nothing to do"

# ── a submodule's changes are comments in the plan, never lines ──
SUB="${FIX}/subsrc"
git init -q --initial-branch=main "${SUB}"
printf 's\n' > "${SUB}/s.txt"
git -C "${SUB}" add s.txt
git -C "${SUB}" -c user.name=t -c user.email=t@example.invalid commit -q -m one
git clone -q "${SUB}" "${HOME}/.config/sub"
mv "${HOME}/.config/sub/.git" "${FIX}/sub.git"
printf 'gitdir: %s\n' "${FIX}/sub.git" > "${HOME}/.config/sub/.git"
git --git-dir="${FIX}/sub.git" config core.worktree "${HOME}/.config/sub"
printf '[submodule ".config/sub"]\n\tpath = .config/sub\n\turl = %s\n' "${SUB}" > "${HOME}/.gitmodules"
df_git update-index --add --cacheinfo "160000,$(git -C "${SUB}" rev-parse HEAD),.config/sub"
df_git -c core.hooksPath=/dev/null commit -q -m "add sub"
printf 's changed\n' > "${HOME}/.config/sub/s.txt"
st peek status --edit
SEEN="$(cat "${FIX}/seen.plan")"
assert_contains "submodule: a comment with its count" "${SEEN}" "# .config/sub: 1 uncommitted"
assert_contains "submodule: its changed file" "${SEEN}" "#    M s.txt"
assert_not_contains "submodule: no action line" "${SEEN}" "shared:.config/sub"

report
