#!/usr/bin/env bash
# raycast_sync and the documentation rule: a binding (its deeplink description) or a snippet (the
# description of the entry that wins its name) without a one-line description fails the step as
# manual `undocumented`, one detail line per finding with the edit that fixes it, the first as
# the fix. A local override documents its placeholder's name. Raycast is a directory, `defaults`
# a shim that reads nothing, the bindings a fixture; nothing reaches the real app or tiers.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

for p in json_sort raycast raycast_link raycast_snippets; do
  ln -s "${ORIG_CONFIG_DIR}/zsh/plugins/${p}.zsh" "${HOME}/.config/zsh/plugins/${p}.zsh"
done
printf '#!/bin/sh\nexit 0\n' > "${FIX}/shims/defaults"; chmod +x "${FIX}/shims/defaults"
mkdir -p "${FIX}/Raycast.app" "${FIX}/shared" "${FIX}/local"
export ARI_DOTFILES_RAYCAST_APP="${FIX}/Raycast.app"
export ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${FIX}/bindings.json"
export ARI_DOTFILES_RAYCAST_SNIPPETS_DIRS="${FIX}/shared:${FIX}/local"
export ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST="${FIX}/local/manifest.json"
# The direct chord is no allow-list work: the binding has no allowId.
printf '%s\n' '{"bindings":[{"path":"extensions/raycast/window-management/left-half","title":"Left Half","chords":["ctrl+opt+h"]}]}' > "${FIX}/bindings.json"
printf '%s\n' '[{"name":"Home","keyword":"~^","text":"OVERRIDE WITH A ~/.local/share/raycast-snippets/snippets.json file"},{"name":"pub","keyword":";pub","text":"public"}]' > "${FIX}/shared/snippets.json"
printf '%s\n' '[{"name":"Home","keyword":"~^","text":"1 Main St"}]' > "${FIX}/local/snippets.json"
nm raycast snippets adopt
assert_eq "adopt rc 0" 0 "${RC}"

check_step() { bump_now_secs 60; nm check --only raycast_sync --json; out_json > /dev/null; }

check_step
assert_eq "undocumented → fail" fail "$(step_get raycast_sync .status)"
assert_eq "reason undocumented" undocumented "$(step_get raycast_sync .reason)"
assert_eq "manual: a human writes the docs" true "$(step_get raycast_sync .manual)"
assert_eq "not actionable" false "$(step_get raycast_sync .actionable)"
detail="$(step_get raycast_sync .detail)"
assert_contains "detail counts the findings" "${detail}" "undocumented='3'"
assert_contains "the binding, with its fix" "${detail}" "binding left-half | fix='dotfiles raycast link edit left-half'"
assert_contains "the local override of a placeholder, fixed in the local tier" "${detail}" "snippet Home (local) | fix='dotfiles raycast snippets edit --local'"
assert_contains "the shared snippet, fixed in the shared tier" "${detail}" "snippet pub (shared) | fix='dotfiles raycast snippets edit --shared'"
assert_eq "fix: the first finding's edit" "dotfiles raycast link edit left-half" "$(step_get raycast_sync .fix)"
assert_not_contains "no snippet text in the detail" "${detail}" "1 Main St"

# Document the binding and the shared snippet; the placeholder's own description does not cover
# the local entry that wins the name.
printf '%s\n' '{"bindings":[{"path":"extensions/raycast/window-management/left-half","title":"Left Half","description":"Move the front window to the left half","chords":["ctrl+opt+h"]}]}' > "${FIX}/bindings.json"
jq -c 'map(.description = "documented")' "${FIX}/shared/snippets.json" > "${FIX}/s.json" && mv "${FIX}/s.json" "${FIX}/shared/snippets.json"
check_step
assert_eq "one finding left → still fail" fail "$(step_get raycast_sync .status)"
assert_eq "the override is the one left" "dotfiles raycast snippets edit --local" "$(step_get raycast_sync .fix)"
assert_contains "and the only one" "$(step_get raycast_sync .detail)" "undocumented='1'"

jq -c 'map(.description = "my address")' "${FIX}/local/snippets.json" > "${FIX}/l.json" && mv "${FIX}/l.json" "${FIX}/local/snippets.json"
check_step
assert_eq "everything documented → ok" ok "$(step_get raycast_sync .status)"
assert_eq "reason in_sync" in_sync "$(step_get raycast_sync .reason)"

# A description is not something Raycast holds: adding them left nothing to import.
nm raycast snippets sync --dry-run
assert_contains "no import pending after documenting" "${OUT}" "pending=0"

# Pending work outranks docs: the actionable verdict comes first.
jq -c '. + [{"name":"new","keyword":";new","text":"n"}]' "${FIX}/shared/snippets.json" > "${FIX}/s.json" && mv "${FIX}/s.json" "${FIX}/shared/snippets.json"
check_step
assert_eq "pending and undocumented → raycast_pending" raycast_pending "$(step_get raycast_sync .reason)"

report
