#!/usr/bin/env bash
# notes: the daily journal, run against a throwaway NOTE_BASE with a fake clock and a fake nvim.
#
# - init makes a repo with .datekeeper and a .gitignore for today.md, once.
# - path registers today: .datekeeper line, a note with the date heading and the daily and weekday
#   templates, today.md pointing at it, both staged and nothing committed.
# - the next day's run commits yesterday's note (one commit per day, trailing whitespace stripped),
#   registers the new day, and leaves an untouched note's content alone.
# - a second run the same day changes nothing.
# - healthcheck names a missing note, an orphan note and an uncommitted past file, and passes clean.
# - fix commits every uncommitted past note; --dry-run commits nothing.
# - open hands nvim the last five notes; an unknown verb or flag is exit 1.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
export ARI_ZSHLIB="${ORIG_CONFIG_DIR}/claude/skills/ari-skill-shellscripts/lib"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${FIX}/gitconfig"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --file "${GIT_CONFIG_GLOBAL}" init.defaultBranch main
export NOTE_BASE="${FIX}/notes"

# The fake clock: date answers for FAKE_DATE (YYYY-MM-DD, noon) whatever format it is asked for.
# The fake nvim records its arguments.
SHIMS="${FIX}/notes-shims"
mkdir -p "${SHIMS}"
cat > "${SHIMS}/date" <<'EOF'
#!/bin/sh
[ -n "${FAKE_DATE:-}" ] || exec /bin/date "$@"
exec /bin/date -j -f '%Y-%m-%d %H:%M:%S' "${FAKE_DATE} 12:00:00" "$@"
EOF
cat > "${SHIMS}/nvim" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "${FIX}/nvim.args"
EOF
chmod +x "${SHIMS}"/*
export PATH="${SHIMS}:${PATH}:/usr/bin:/bin"   # notes uses sed, comm and cut, which the world leaves off PATH
NOTES="${ORIG_CONFIG_DIR}/bin/notes"

notes() { RC=0; OUT="$(FAKE_DATE="${DAY}" zsh "${NOTES}" "$@" 2>"${FIX}/err")" || RC=$?; ERR="$(cat "${FIX}/err")"; }
g() { git -C "${NOTE_BASE}" "$@"; }
commits() { g log --format=%s | tr '\n' '|'; }

# ── init ──
DAY=2026-11-16
notes init
assert_eq "init: exit 0" 0 "${RC}"
assert_eq "init: .datekeeper is tracked" ".datekeeper" "$(g ls-files .datekeeper)"
assert_eq "init: today.md is gitignored" "today.md" "$(cat "${NOTE_BASE}/.gitignore")"
assert_eq "init: one first commit" "first commit|" "$(commits)"
notes init
assert_eq "init: a second init adds no commit" "first commit|" "$(commits)"

# ── path: today registered ──
mkdir -p "${NOTE_BASE}/etc/tasks"
printf -- '- [ ] water the bonsai   \n' > "${NOTE_BASE}/etc/tasks/daily.md"
printf -- '- [ ] monday standup\n' > "${NOTE_BASE}/etc/tasks/monday.md"
printf -- '- [ ] tuesday review\n' > "${NOTE_BASE}/etc/tasks/tuesday.md"
g add etc && g commit -q -m templates
notes path
assert_eq "path: exit 0" 0 "${RC}"
assert_eq "path: prints today's note" "${NOTE_BASE}/2026/Nov/16.md" "${OUT}"
assert_eq "path: .datekeeper lists today" "2026/Nov/16" "$(awk NF "${NOTE_BASE}/.datekeeper")"
assert_eq "path: the note is the heading, the daily and the Monday template" \
  "# Nov 16, 2026|- [ ] water the bonsai   |- [ ] monday standup|" "$(tr '\n' '|' < "${NOTE_BASE}/2026/Nov/16.md")"
assert_eq "path: today.md points at the note" "${NOTE_BASE}/2026/Nov/16.md" "$(readlink "${NOTE_BASE}/today.md")"
assert_eq "path: today's note and .datekeeper are staged" "A  2026/Nov/16.md|M  .datekeeper|" "$(g status --porcelain | LC_ALL=C sort | tr '\n' '|')"
assert_eq "path: nothing committed for today" "templates|first commit|" "$(commits)"
echo "wrote something today" >> "${NOTE_BASE}/2026/Nov/16.md"
notes path
assert_eq "path: a second run the same day keeps today's writing" "wrote something today" "$(tail -n 1 "${NOTE_BASE}/2026/Nov/16.md")"
assert_eq "path: and adds no .datekeeper line" 1 "$(awk NF "${NOTE_BASE}/.datekeeper" | wc -l | tr -d ' ')"

# ── rollover ──
DAY=2026-11-17
notes path
assert_eq "rollover: exit 0" 0 "${RC}"
# The same-day second run committed .datekeeper already (it was staged and dirty); the rollover adds one
# commit for yesterday's note.
assert_eq "rollover: yesterday committed, one commit for the day" \
  "Journal entry for 2026/Nov/16|Update .datekeeper|templates|first commit|" "$(commits)"
assert_eq "rollover: yesterday's note committed whole" "wrote something today" "$(g show HEAD:2026/Nov/16.md | tail -n 1)"
assert_eq "rollover: trailing whitespace stripped before the commit" "- [ ] water the bonsai" "$(g show HEAD:2026/Nov/16.md | sed -n 2p)"
assert_eq "rollover: today is the Tuesday note" "- [ ] tuesday review" "$(tail -n 1 "${NOTE_BASE}/2026/Nov/17.md")"
assert_eq "rollover: today.md moved to today" "${NOTE_BASE}/2026/Nov/17.md" "$(readlink "${NOTE_BASE}/today.md")"
assert_eq "rollover: only today's note and .datekeeper are pending" "A  2026/Nov/17.md|M  .datekeeper|" "$(g status --porcelain | LC_ALL=C sort | tr '\n' '|')"

# ── healthcheck ──
notes healthcheck
assert_eq "healthcheck: clean is exit 0" 0 "${RC}"
assert_contains "healthcheck: says so" "${ERR}" "all checks passed"
mkdir -p "${NOTE_BASE}/2026/Oct"; echo "# stray" > "${NOTE_BASE}/2026/Oct/01.md"
echo "late edit" >> "${NOTE_BASE}/2026/Nov/16.md"
echo "2026/Nov/02" >> "${NOTE_BASE}/.datekeeper"
notes healthcheck
assert_eq "healthcheck: problems are exit 1" 1 "${RC}"
assert_contains "healthcheck: a registered date with no note" "${ERR}" "missing note for 2026/Nov/02"
assert_contains "healthcheck: a note no date registers" "${ERR}" "orphan note, not in .datekeeper: 2026/Oct/01"
assert_contains "healthcheck: an edited past note" "${ERR}" "uncommitted past file: 2026/Nov/16.md"
assert_contains "healthcheck: counts them" "${ERR}" "issues found | count='4'"
sed -i '' '/2026\/Nov\/02/d' "${NOTE_BASE}/.datekeeper"; rm -rf "${NOTE_BASE}/2026/Oct"

# ── fix ──
before="$(commits)"
notes fix --dry-run
assert_eq "fix --dry-run: makes no commit" "${before}" "$(commits)"
assert_contains "fix --dry-run: names the commit it would make" "${ERR}" "would commit | file='2026/Nov/16.md' message='Journal entry for 2026/Nov/16'"
notes fix
assert_eq "fix: commits the edited past note" "Journal entry for 2026/Nov/16" "$(g log -1 --format=%s -- 2026/Nov/16.md)"
assert_eq "fix: the late edit is in it" "late edit" "$(g show HEAD:2026/Nov/16.md | tail -n 1)"
assert_eq "fix: today's note is still uncommitted" "" "$(g log --format=%s -- 2026/Nov/17.md)"

# ── open ──
for d in 18 19 20 21; do DAY="2026-11-${d}"; notes path; done
DAY=2026-11-22
notes open
assert_eq "open: exit 0" 0 "${RC}"
assert_eq "open: nvim gets the last five notes, oldest first" \
  "2026/Nov/18.md|2026/Nov/19.md|2026/Nov/20.md|2026/Nov/21.md|2026/Nov/22.md|" "$(head -n 5 "${FIX}/nvim.args" | tr '\n' '|')"
assert_contains "open: today on the left, yesterday on the right" "$(sed -n 7p "${FIX}/nvim.args")" "5b | belowright vsp | 4b"

# ── usage ──
notes bogus
assert_eq "usage: an unknown verb is exit 1" 1 "${RC}"
assert_contains "usage: it names the valid verbs" "${ERR}" "valid='open, path, init, fix, healthcheck'"
notes --bogus
assert_eq "usage: an unknown flag is exit 1" 1 "${RC}"

report
