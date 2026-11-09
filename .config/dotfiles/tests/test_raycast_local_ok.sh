#!/usr/bin/env bash
# raycast_sync with snippets: a local-only snippet (no shared placeholder) is a valid end state,
# so the step is ok and `snippets fmt` adds nothing to shared; a shared placeholder nothing
# overrides still warns. Raycast is a directory, the bindings an empty fixture; nothing reaches the real app or tiers.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# The raycast plugins the step loads, from the checkout under test.
for p in json_sort raycast raycast_link raycast_snippets; do
  ln -s "${ORIG_CONFIG_DIR}/zsh/plugins/${p}.zsh" "${HOME}/.config/zsh/plugins/${p}.zsh"
done
mkdir -p "${FIX}/Raycast.app" "${FIX}/shared" "${FIX}/local"
printf '{"bindings":[]}\n' > "${FIX}/bindings.json"
export ARI_DOTFILES_RAYCAST_APP="${FIX}/Raycast.app"
export ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${FIX}/bindings.json"
export ARI_DOTFILES_RAYCAST_SNIPPETS_SHARED_FILE="${FIX}/shared/snippets.json"
export ARI_DOTFILES_RAYCAST_SNIPPETS_LOCAL_FILE="${FIX}/local/snippets.json"
export ARI_DOTFILES_RAYCAST_SNIPPETS_MERGED="${FIX}/merged.json"
export ARI_DOTFILES_RAYCAST_SNIPPETS_MERGE_NIX="${ORIG_CONFIG_DIR}/dotfiles/nix/lib/raycast-snippets-merge.nix"
export ARI_DOTFILES_RAYCAST_SNIPPETS_NIX="${FIX}/tools/nix" # the real one: the world's nix is a shim
export ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST="${FIX}/local/manifest.json"
printf '[\n  {\n    "description": "a public line",\n    "keyword": ";pub",\n    "name": "pub",\n    "text": "public"\n  }\n]\n' > "${FIX}/shared/snippets.json"
printf '[\n  {\n    "description": "an email address",\n    "keyword": "@@s",\n    "name": "Sweedler.com email",\n    "text": "a@example.invalid"\n  }\n]\n' > "${FIX}/local/snippets.json"
snippets_merge; nm raycast snippets adopt
assert_eq "adopt rc 0" 0 "${RC}"

check_step() { snippets_merge; bump_now_secs 60; nm check --only raycast_sync --json; out_json > /dev/null; }

check_step
assert_eq "local-only snippet → raycast_sync ok" ok "$(step_get raycast_sync .status)"
assert_eq "reason in_sync" in_sync "$(step_get raycast_sync .reason)"
assert_not_contains "no parity warn for the local-only snippet" "$(step_get raycast_sync .detail)" "Sweedler.com email"

shared_before="$(cat "${FIX}/shared/snippets.json")"
snippets_merge; nm raycast snippets fmt
assert_eq "fmt rc 0" 0 "${RC}"
assert_contains "fmt reports nothing to do" "${OUT}" "snippets: already canonical, nothing to format"
assert_not_contains "fmt has no placeholder count" "${OUT}" "placeholders_added"
assert_eq "fmt leaves shared byte-identical (no placeholder added)" "${shared_before}" "$(cat "${FIX}/shared/snippets.json")"

snippets_merge; nm raycast snippets check
assert_eq "check: in parity, no warnings" $'snippets: tiers in parity | entries=2\nwarnings=0' "${OUT}"

# A shared placeholder nothing overrides still warns: Raycast would expand to the reminder.
jq '. + [{"name":"orphan","keyword":"~o","description":"a placeholder","text":"OVERRIDE WITH A ~/.local/share/dotfiles/nix/raycast-snippets.json file"}]' \
  "${FIX}/shared/snippets.json" > "${FIX}/s.json" && mv "${FIX}/s.json" "${FIX}/shared/snippets.json"
snippets_merge; nm raycast snippets adopt
check_step
assert_eq "active placeholder → warn" warn "$(step_get raycast_sync .status)"
assert_eq "reason raycast_parity" raycast_parity "$(step_get raycast_sync .reason)"
assert_contains "detail names the placeholder" "$(step_get raycast_sync .detail)" "placeholder active: orphan (~o)"
assert_not_contains "detail still says nothing of the local-only snippet" "$(step_get raycast_sync .detail)" "Sweedler.com email"

report
