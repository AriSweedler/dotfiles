#!/usr/bin/env bash
# ldf-link against fixture repos (no git, so every file under a layer counts): local/<machine> over a
# tag, the refusal of one path from two tags, an identical real file replaced by a link, a differing
# one refused and left alone, a stale link pruned, a dry run that changes nothing, and a second run
# that has nothing to change.
set -u
LDF_LINK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)/ldf-link"

fails=0
assert() { # assert <name> <command...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

W="$(mktemp -d "${TMPDIR:-/tmp}/ldf-link.XXXXXX")"
trap 'rm -rf "${W}"' EXIT
REPO="${W}/repo" TARGET="${W}/home/.local"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
run() { LDF_REPO="${REPO}" LDF_TARGET="${TARGET}" ARI_DOTFILES_MACHINE="${MACHINE}" zsh "${LDF_LINK}" "$@" > "${W}/out" 2> "${W}/err"; RC=$?; }

# ── the world: ganymede carries nixos and pi; both tags hold share/x, only pi holds share/y ──
put "${REPO}/machines" $'# fixture\nozone mac\nganymede nixos pi   # the Pi'
put "${REPO}/nixos/share/common" "nixos common"
put "${REPO}/pi/share/only-pi" "pi only"
put "${REPO}/local/ganymede/share/dotfiles/machine-name" "ganymede"
put "${REPO}/local/ganymede/share/common" "ganymede's own common"    # local over nixos
put "${REPO}/mac/share/mac-only" "mac"
MACHINE=ganymede

run
assert "dry run: exit 0" test "${RC}" = 0
assert "dry run: links nothing" test ! -e "${TARGET}/share/only-pi"
assert "dry run: says what it would link" grep -q "^would link ${TARGET}/share/only-pi" "${W}/out"

run --execute
assert "execute: exit 0" test "${RC}" = 0
assert "a tag's file is linked" test "$(readlink "${TARGET}/share/only-pi")" = "${REPO}/pi/share/only-pi"
assert "local/<machine> wins over a tag" test "$(readlink "${TARGET}/share/common")" = "${REPO}/local/ganymede/share/common"
assert "another machine's tag is not linked" test ! -e "${TARGET}/share/mac-only"

run
assert "second run: nothing to change" grep -q "^nothing to change (ganymede: local/ganymede over nixos pi)" "${W}/out"

# ── two tags, one path, not settled by local: refused, nothing linked ──
put "${REPO}/nixos/share/both" "nixos copy"
put "${REPO}/pi/share/both" "pi copy"
put "${REPO}/pi/share/new-pi" "new"
run --execute
assert "two-tag path: exit 1" test "${RC}" = 1
assert "two-tag path: names the path and both tags" grep -q "conflict share/both: in tags nixos and pi" "${W}/err"
assert "two-tag path: links nothing at all" test ! -e "${TARGET}/share/new-pi"

# local/<machine> settles it
put "${REPO}/local/ganymede/share/both" "ganymede picks"
run --execute
assert "settled by local: exit 0" test "${RC}" = 0
assert "settled by local: links local's copy" test "$(readlink "${TARGET}/share/both")" = "${REPO}/local/ganymede/share/both"

# ── real files where links go ──
put "${REPO}/local/ganymede/share/same" "same bytes"
put "${TARGET}/share/same" "same bytes"
put "${REPO}/local/ganymede/share/differs" "repo's"
put "${TARGET}/share/differs" "machine's own edit"
run --execute
assert "identical real file: replaced by the link" test "$(readlink "${TARGET}/share/same")" = "${REPO}/local/ganymede/share/same"
assert "differing real file: exit 1" test "${RC}" = 1
assert "differing real file: named" grep -q "refuse ${TARGET}/share/differs: differs from" "${W}/err"
assert "differing real file: left as it was" test "$(cat "${TARGET}/share/differs")" = "machine's own edit"

# ── a stale link is pruned; a link that points outside the repo is left alone ──
rm "${REPO}/pi/share/only-pi"
rm "${TARGET}/share/differs"
put "${W}/elsewhere" "not the repo's"
ln -s "${W}/elsewhere" "${TARGET}/share/foreign"
run --execute
assert "stale link: exit 0" test "${RC}" = 0
assert "stale link: pruned" test ! -L "${TARGET}/share/only-pi"
assert "a link outside the repo is never pruned" test "$(readlink "${TARGET}/share/foreign")" = "${W}/elsewhere"

# ── a machine the file does not list ──
MACHINE=nobody; run; MACHINE=ganymede
assert "unlisted machine: exit 1" test "${RC}" = 1
assert "unlisted machine: says so" grep -q "machine 'nobody' is not in" "${W}/err"

(( fails == 0 )) && echo "all passed" || { echo "${fails} failed"; exit 1; }
