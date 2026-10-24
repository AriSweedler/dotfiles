#!/usr/bin/env bash
# `verify --edit` opens the report a human annotates (the Desktop one, else the newest one a run
# moved aside as edited) in $EDITOR and runs nothing: no lock, no run, no state, no commit; the
# only write is the editor's. A save that loses the line-1 marker is caught (the file would turn
# foreign); the last line is the next step, the report's own "feed this to Claude" line.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
STATE="${ARI_DOTFILES_STATE_DIR}"
DESK="${ARI_DOTFILES_DESKTOP_DIR}"
REPORT="${DESK}/new-machine-FAILED.md"
GOLDEN="${TESTS_DIR}/fixtures/report-golden.md"
MARKER="$(head -n 1 "${GOLDEN}")"

EDITORS="${FIX}/editors"
OPENED="${FIX}/opened"
mkdir -p "${EDITORS}"
# editor NAME AWK: records the files it is given, then rewrites each with AWK.
editor() {
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\nfor f in "$@"; do awk %s "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done\n' \
    "${OPENED}" "'$2'" > "${EDITORS}/$1"
  chmod +x "${EDITORS}/$1"
}
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\n' "${OPENED}" > "${EDITORS}/noop"; chmod +x "${EDITORS}/noop"
editor note 'END { print ""; print "Ari: the brew row is a false alarm." } { print }'
editor drop_marker 'NR == 1 { next } { print }'
editor drop_feed '/^    claude "/ { next } { print }'
printf '#!/bin/sh\nexit 3\n' > "${EDITORS}/fail"; chmod +x "${EDITORS}/fail"

snapshot() { find "${HOME}" -exec stat -f '%N %z %m' {} + | sort; }
# edit EDITOR ARGS...: `dotfiles verify --edit ARGS` with that editor, no terminal.
edit() {
  local ed="$1"; shift
  rm -f "${OPENED}"
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" verify --edit "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
opened() { cat "${OPENED}" 2>/dev/null; }

# ── nothing to edit: one line naming the last run, nothing opened, nothing written ──
before="$(snapshot)"
edit noop
assert_eq "none: exit 0" 0 "${RC}"
assert_eq "none: says so" "no verify report to edit" "${OUT}"
assert_eq "none: no editor" "" "$(opened)"
assert_eq "none: nothing written" "${before}" "$(snapshot)"
mkdir -p "${STATE}"
printf '{"schema":1,"ts":"2026-09-17T00:26:40Z","status":"fail"}\n' > "${STATE}/last_result.json"
edit noop
assert_eq "none: names the last run" "no verify report to edit; last verify 2026-09-17T00:26:40Z: fail" "${OUT}"

# ── the Desktop report, unchanged: no change, the feed line next, nothing else written ──
cp "${GOLDEN}" "${REPORT}"
before="$(snapshot)"
edit noop
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_eq "unchanged: opens the Desktop report" "${REPORT}" "$(opened)"
assert_contains "unchanged: no change" "${OUT}" "verify: no change"
assert_contains "unchanged: next is the feed line" "${OUT}" "next: in a terminal, cd ~ and paste:"
assert_contains "unchanged: the feed line itself" "${OUT}" '  claude "Read /tmp/nmtest/home/Desktop/new-machine-FAILED.md'
assert_eq "unchanged: nothing written" "${before}" "$(snapshot)"
assert_no_file "unchanged: no lock" "${STATE}/lock.d"
assert_no_file "unchanged: no run dir" "${STATE}/runs"
assert_no_file "unchanged: no verify log" "${STATE}/verify/log.txt"

# ── notes: saved in place, the marker kept, still no run or state ──
edit note
assert_eq "notes: exit 0" 0 "${RC}"
assert_contains "notes: saved" "${OUT}" "verify: notes saved"
assert_contains "notes: in the file" "$(cat "${REPORT}")" "Ari: the brew row is a false alarm."
assert_eq "notes: the marker survives" "${MARKER}" "$(head -n 1 "${REPORT}")"
assert_not_contains "notes: no marker warning" "${ERR}" "marker"
assert_no_file "notes: no run dir" "${STATE}/runs"

# ── the marker lost, no terminal: kept as saved, exit 1 with the marker and the resume ──
cp "${GOLDEN}" "${REPORT}"
edit drop_marker
assert_eq "lost marker: exit 1" 1 "${RC}"
assert_contains "lost marker: says it turns foreign" "${ERR}" "verify now treats this file as foreign"
assert_contains "lost marker: quotes the marker" "${ERR}" "marker='${MARKER}'"
assert_contains "lost marker: the resume" "${ERR}" "fix='dotfiles verify --edit'"
assert_eq "lost marker: the save is kept" "# new-machine weekly check FAILED — testhost, 2026-09-10 00:26" "$(head -n 1 "${REPORT}")"

# The terminal's restore: a mangled marker is replaced, a deleted one put back above line 1.
zfn ../verify.zsh verify::_restore_marker "${REPORT}" "${MARKER}"
assert_eq "restore: exit 0" 0 "${RC}"
assert_eq "restore: deleted marker put back" "${MARKER}" "$(head -n 1 "${REPORT}")"
assert_eq "restore: the rest untouched" "$(tail -n +2 "${GOLDEN}")" "$(tail -n +2 "${REPORT}")"
{ printf '<!-- new-machine-report v1 fingerprint=XX -->\n'; tail -n +2 "${GOLDEN}"; } > "${REPORT}"
zfn ../verify.zsh verify::_restore_marker "${REPORT}" "${MARKER}"
assert_eq "restore: mangled marker replaced" "${MARKER}" "$(head -n 1 "${REPORT}")"
assert_eq "restore: no line added" "$(wc -l < "${GOLDEN}")" "$(wc -l < "${REPORT}")"

# ── no feed line: the next step is a fresh report ──
cp "${GOLDEN}" "${REPORT}"
edit drop_feed
assert_eq "no feed: exit 0" 0 "${RC}"
assert_contains "no feed: next is --force-report" "${OUT}" "next: dotfiles verify --force-report"

# ── the editor fails: exit 1, the file as it was ──
cp "${GOLDEN}" "${REPORT}"
edit fail
assert_eq "editor fails: exit 1" 1 "${RC}"
assert_contains "editor fails: says so" "${ERR}" "editor exited non-zero"

# ── which report: ours beside a foreign canonical file; else the newest moved aside as edited ──
printf 'my own notes\n' > "${REPORT}"
COLLIDE="${DESK}/new-machine-FAILED.d4a0c230.md"
cp "${GOLDEN}" "${COLLIDE}"
printf '{"schema":1,"ts":"2026-09-17T00:26:40Z","status":"fail","report_path":"%s"}\n' "${COLLIDE}" > "${STATE}/last_result.json"
edit noop
assert_eq "collision: opens ours, not the foreign file" "${COLLIDE}" "$(opened)"
rm -f "${REPORT}" "${COLLIDE}"
cp "${GOLDEN}" "${DESK}/new-machine-FAILED.2026-09-03-aaaaaaaa.edited.md"
cp "${GOLDEN}" "${DESK}/new-machine-FAILED.2026-09-10-bbbbbbbb.edited.md"
touch -t 202609030000 "${DESK}/new-machine-FAILED.2026-09-03-aaaaaaaa.edited.md"
touch -t 202609100000 "${DESK}/new-machine-FAILED.2026-09-10-bbbbbbbb.edited.md"
edit noop
assert_eq "edited: the newest one" "${DESK}/new-machine-FAILED.2026-09-10-bbbbbbbb.edited.md" "$(opened)"

# ── usage: --edit runs nothing, so the flags that shape a run do not apply ──
edit noop --json
assert_eq "--edit --json is a usage error" 64 "${RC}"
edit noop --force-report
assert_eq "--edit --force-report is a usage error" 64 "${RC}"
edit noop --show
assert_eq "--edit --show is a usage error" 64 "${RC}"
assert_eq "usage errors open nothing" "" "$(opened)"
nm verify --help
assert_contains "help: edit in Usage" "${OUT}" "dotfiles verify edit"
assert_contains "help: --show in Usage" "${OUT}" "verify --show"
assert_contains "help: the edit subcommand" "${OUT}" "  edit  open the Desktop report"
assert_contains "help: --edit in Flags" "${OUT}" "  --edit          edit: the same as the edit subcommand"
assert_no_mutation "read-only throughout"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
