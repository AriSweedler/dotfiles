#!/usr/bin/env bash
# tier::commit in a local tier with no remote (a machine whose local tier stays on it): the commit
# lands, the push is skipped with a note, and the call succeeds.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
mkdir -p "${XDG_DATA_HOME}/new-machine"
printf 'brew "jq"\n' > "${XDG_DATA_HOME}/new-machine/Brewfile"

hermetic_env
RC=0
env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c '
  for f in "$1"/lib/*.zsh(N); do source "${f}"; done
  tier::commit local "add jq" "$2"' _ "${ORIG_CONFIG_DIR}/dotfiles" "${XDG_DATA_HOME}/new-machine/Brewfile" \
  > "${FIX}/out" 2> "${FIX}/err" || RC=$?
assert_eq "no remote: exit 0" 0 "${RC}"
assert_eq "no remote: committed" "add jq" "$(ldf_git log -1 --format=%s)"
assert_contains "no remote: says there is nothing to push" "$(cat "${FIX}/err")" "local tier has no remote; committed here, nothing to push"
assert_not_contains "no remote: no push failure" "$(cat "${FIX}/err")" "push failed"
report
