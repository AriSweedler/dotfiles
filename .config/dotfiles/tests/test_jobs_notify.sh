#!/usr/bin/env bash
# `jobs run` tells the user how a job ended through terminal-notifier: a banner on success, an
# alert on failure or timeout, and nothing for an ending the plugin's '# notifies:' line claims.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
JOBS_DF="${HOME}/.config/dotfiles/jobs"
mkdir -p "${JOBS_DF}"

# plugin NAME HEADER BODY: a documented unlock plugin in the shared root; HEADER is extra header lines.
plugin() {
  printf '#!/usr/bin/env zsh\n# triggers: unlock\n%s# Says how it ends, to prove the engine reports it.\n%s\n' "$2" "$3" > "${JOBS_DF}/$1"
  chmod +x "${JOBS_DF}/$1"
}
# run NAME: `dotfiles jobs run NAME` with an empty notifier log; `posted` is what the fake notifier saw.
run() { shim_logs_reset; nm jobs run "$1"; }
posted() { shim_log terminal-notifier; }

plugin ok_engine '' 'print -r -- "all good"'
run ok_engine
assert_eq "ok: exit 0" 0 "${RC}"
assert_contains "ok: the engine's banner carries the summary line" "$(posted)" "-message ok_engine ok in"
assert_contains "ok: ... the plugin's last line" "$(posted)" "all good"
assert_contains "ok: the banner comes down" "$(posted)" "-remove dotfiles-jobs"

plugin ok_self $'# notifies: ok\n' 'print -r -- "told you myself"'
run ok_self
assert_eq "notifies ok: exit 0" 0 "${RC}"
assert_not_contains "notifies ok: no engine banner" "$(posted)" "-message"
assert_contains "notifies ok: a stale failure alert still comes down" "$(posted)" "-remove dotfiles-jobs-ok_self"

plugin fail_engine '' 'print -r -- "broke"; exit 3'
run fail_engine
assert_eq "fail: the plugin's rc" 3 "${RC}"
assert_contains "fail: the engine's alert" "$(posted)" "fail_engine failed (rc 3)"
assert_contains "fail: the alert carries the last line and opens the log" "$(posted)" "broke — click to open the log"

plugin fail_self $'# notifies: fail\n' 'print -r -- "login needed, said so"; exit 1'
run fail_self
assert_eq "notifies fail: the plugin's rc" 1 "${RC}"
assert_eq "notifies fail: the engine posts nothing" "" "$(posted)"

plugin slow_self $'# notifies: fail\n# timeout: 1\n' 'sleep 5'
run slow_self
assert_eq "timeout: rc 124" 124 "${RC}"
assert_contains "timeout: the engine's alert, whatever the plugin notifies" "$(posted)" "slow_self timed out"

report
