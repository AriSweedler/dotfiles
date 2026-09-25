#!/usr/bin/env bash
# The local-dotfiles allowlist template admits share/new-machine/ but still excludes secrets.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
BARE="${FIX}/ldf.git"
WORK="${FIX}/ldfwork"
git init -q --bare --initial-branch=main "${BARE}"
mkdir -p "${BARE}/info" "${WORK}/share/new-machine"
cp "${REPO_DIR}/local-dotfiles-exclude" "${BARE}/info/exclude"
printf 'brew "gh"\n' > "${WORK}/share/new-machine/Brewfile"
printf 'formula libtiff  # library\n' > "${WORK}/share/new-machine/Brewfile.ignore"
printf 'export TOKEN=nope\n' > "${WORK}/share/new-machine/x.secret.zsh"
g() { git --git-dir="${BARE}" --work-tree="${WORK}" "$@"; }

rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/Brewfile) || rc=$?
assert_eq "share/new-machine/Brewfile is tracked-eligible" 1 "${rc}"
rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/Brewfile.ignore) || rc=$?
assert_eq "share/new-machine/Brewfile.ignore is tracked-eligible" 1 "${rc}"
rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/x.secret.zsh) || rc=$?
assert_eq "share/new-machine/x.secret.zsh stays excluded" 0 "${rc}"

(cd "${WORK}" && g add -A .)
staged="$(g diff --cached --name-only | sort)"
assert_eq "git add -A stages exactly the two Brewfiles" "share/new-machine/Brewfile
share/new-machine/Brewfile.ignore" "${staged}"

report
