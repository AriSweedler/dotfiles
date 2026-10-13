#!/usr/bin/env bash
# `verify --show` prints the current report and nothing else happens: the Desktop file as is,
# else the newest archive with a note on stderr, else one line naming the last run; no lock,
# no run dir, no log, no banner, nothing written anywhere in the world.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
STATE="${ARI_DOTFILES_STATE_DIR}"
REPORT="${ARI_DOTFILES_DESKTOP_DIR}/new-machine-FAILED.md"
GOLDEN="${TESTS_DIR}/fixtures/report-golden.md"

# show <label>: one `verify --show` run, then the invariants every case shares.
# Every path under the world's HOME with its size and mtime; any write changes it.
snapshot() { find "${HOME}" -exec stat -f '%N %z %m' {} + | sort; }
show() {
  local before after
  before="$(snapshot)"
  shim_logs_reset
  nm verify --show
  after="$(snapshot)"
  if [[ "${before}" == "${after}" ]]; then pass "$1: nothing written"
  else fail "$1: nothing written" "$(diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") | head -n 5)"
  fi
  assert_no_file "$1: no lock" "${STATE}/lock.d"
  assert_eq "$1: no banner" "" "$(shim_log terminal-notifier)"
  assert_no_mutation "$1: read-only"
}

# Case 3: nothing at all.
show none
assert_eq "none: exits 0" 0 "${RC}"
assert_eq "none: one line, no last run" "no verify report" "${OUT}"
assert_no_file "none: state dir not created" "${STATE}"

mkdir -p "${STATE}"
printf '%s\n' "2026-09-03 00:10:00 [verify] status='ok' fingerprint='' report='none' undeclared='0'" \
  "2026-09-10 00:26:40 [verify] status='fail' fingerprint='d4a0c230f112d501' report='written' undeclared='12'" > "${STATE}/verify.log"
show trail
assert_eq "trail: last status line of the trail" "no verify report; last verify 2026-09-10 00:26:40: fail" "${OUT}"

printf '{"schema":1,"ts":"2026-09-17T00:26:40Z","status":"warn"}\n' > "${STATE}/last_result.json"
show last_result
assert_eq "last_result: wins over the trail" "no verify report; last verify 2026-09-17T00:26:40Z: warn" "${OUT}"

# Case 2: archives only; the newest by mtime is shown, as is, the note on stderr.
mkdir -p "${STATE}/reports"
printf '# older\n' > "${STATE}/reports/2026-09-10-aaaaaaaa.md"
cp "${GOLDEN}" "${STATE}/reports/2026-09-03-bbbbbbbb.md"
touch -t 202609100026 "${STATE}/reports/2026-09-10-aaaaaaaa.md"
touch -t 202609170026 "${STATE}/reports/2026-09-03-bbbbbbbb.md"
show archive
assert_eq "archive: exits 0" 0 "${RC}"
if cmp -s "${FIX}/nm.out" "${GOLDEN}"; then pass "archive: stdout is the newest archive byte for byte"
else fail "archive: stdout is the newest archive byte for byte" "$(diff "${FIX}/nm.out" "${GOLDEN}" | head -n 5)"; fi
assert_contains "archive: stderr says archived and when" "${ERR}" "archived report from 2026-09-17 00:26"
assert_contains "archive: stderr names the file as ui::paths shows it" "${ERR}" "\$XDG_STATE_HOME/new-machine/reports/2026-09-03-bbbbbbbb.md"

# Case 1: the Desktop report wins over every archive.
cp "${GOLDEN}" "${REPORT}"
printf '# newest archive\n' > "${STATE}/reports/2026-09-24-cccccccc.md"
show desktop
assert_eq "desktop: exits 0" 0 "${RC}"
if cmp -s "${FIX}/nm.out" "${REPORT}"; then pass "desktop: stdout is the Desktop file byte for byte"
else fail "desktop: stdout is the Desktop file byte for byte" "$(diff "${FIX}/nm.out" "${REPORT}" | head -n 5)"; fi
assert_eq "desktop: nothing on stderr" "" "${ERR}"
assert_no_file "no run directory" "${STATE}/runs"
assert_no_file "no verify log" "${STATE}/verify/log.txt"

# --show runs nothing, so the flags that shape a run are usage errors.
nm verify --show --json
assert_eq "--show --json is a usage error" 64 "${RC}"
nm verify --force-report --show
assert_eq "--force-report --show is a usage error" 64 "${RC}"
nm verify --help
assert_contains "help lists --show" "${OUT}" "  --show           print the current report"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
