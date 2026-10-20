#!/usr/bin/env bash
# `dotfiles logs`: the push logs printed, and `logs --edit` opening them in $EDITOR, all at once
# and read-only for the vi family, through an editor that records its argv. --edit needs a
# terminal: /usr/bin/script gives it one.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
LOGS="${XDG_STATE_HOME}/dotfiles/push"
EDITORS="${FIX}/editors"
ARGV="${FIX}/argv"
mkdir -p "${EDITORS}"
# recorder NAME: an editor that writes each argument on its own line to $ARGV.
recorder() { printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\n' "${ARGV}" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
recorder vim
recorder plain

# on_tty EDITOR ARGS...: `dotfiles ARGS` on a pseudo-terminal with that $EDITOR; RC is its exit.
on_tty() {
  local ed="$1"; shift
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${ed}")
  rm -f "${ARGV}"
  RC=0
  env -i "${HERMETIC_ENV[@]}" /usr/bin/script -q /dev/null "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    < /dev/null > "${FIX}/tty.out" 2>&1 || RC=$?
  OUT="$(tr -d '\r' < "${FIX}/tty.out")"
  GOT="$(cat "${ARGV}" 2>/dev/null)"
}

# ── no logs yet ──
nm logs
assert_eq "no logs: exit 0" 0 "${RC}"
assert_contains "no logs: says so" "${OUT}${ERR}" "no push logs yet"
[[ -x /usr/bin/script ]] || abort "/usr/bin/script is needed for a terminal"
on_tty "${EDITORS}/vim" logs --edit
assert_eq "no logs, --edit: exit 0" 0 "${RC}"
assert_eq "no logs, --edit: no editor" "" "${GOT}"

mkdir -p "${LOGS}"
printf '# 2026-09-01T10:00:00Z dotfiles push -> shared\n[INFO] Pushed | main@abc\n' > "${LOGS}/shared.log"
printf '# 2026-08-31T10:00:00Z dotfiles push -> shared\n[INFO] Pushed | main@old\n' > "${LOGS}/shared.log.bak.1"
printf '# 2026-09-02T10:00:00Z dotfiles push -> local\n[ERROR] rejected\n' > "${LOGS}/local.log"
printf '# 2026-08-30T10:00:00Z dotfiles push -> local\n[INFO] Pushed\n' > "${LOGS}/local.log.bak.1"
# Every name and every byte under the log dir, to show --edit writes nothing.
log_dir_state() { local f; for f in "${LOGS}"/* "${LOGS}"/.*; do [[ -f "${f}" ]] || continue; printf '== %s\n' "${f}"; cat "${f}"; done; }
before="$(log_dir_state)"

# ── plain logs, unchanged ──
nm logs --repo shared
assert_eq "plain: exit 0" 0 "${RC}"
assert_contains "plain: the header" "${OUT}" "=== shared.log ("
assert_contains "plain: the body" "${OUT}" "[INFO] Pushed | main@abc"

# ── --edit ──
nm logs --edit
assert_eq "--edit, no terminal: 64" 64 "${RC}"
assert_contains "--edit, no terminal: why" "${ERR}" "logs --edit needs a terminal"

on_tty "${EDITORS}/vim" logs --edit
assert_eq "--edit: exit 0" 0 "${RC}"
assert_eq "--edit: every log at once, read-only for vim" "-R
${LOGS}/local.log
${LOGS}/shared.log" "${GOT}"
assert_not_contains "--edit: prints no log" "${OUT}" "=== "

on_tty "${EDITORS}/vim" logs --edit --previous
assert_eq "--previous: the .bak.1 of each" "-R
${LOGS}/local.log.bak.1
${LOGS}/shared.log.bak.1" "${GOT}"

on_tty "${EDITORS}/vim" logs --edit --repo shared --previous
assert_eq "--repo with --previous: that one" "-R
${LOGS}/shared.log.bak.1" "${GOT}"

on_tty "${EDITORS}/plain --wait" logs --repo local --edit
assert_eq "an editor not of the vi family: its words, no -R" "--wait
${LOGS}/local.log" "${GOT}"

on_tty "${EDITORS}/vim" logs --edit --repo nope
assert_eq "an unknown repo: exit 1" 1 "${RC}"
assert_contains "an unknown repo: names the valid ones" "${OUT}" "valid_repos='shared, local"
assert_eq "an unknown repo: no editor" "" "${GOT}"

assert_eq "nothing written in the log dir" "${before}" "$(log_dir_state)"

report
