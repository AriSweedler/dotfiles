#!/usr/bin/env bash
# brew::alias_map: aliases, oldnames, receipt-only kegs, tap-qualified keys, ambiguity.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift

zfn brew.zsh brew::inventory
assert_eq "inventory exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/inventory.json"
zfn brew.zsh brew::info_installed
assert_eq "info_installed exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/info.json"

zfn brew.zsh brew::alias_map "${FIX}/info.json" "${FIX}/inventory.json"
assert_eq "alias_map exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/alias.json"
assert_json "kubectl → kubernetes-cli" "${FIX}/alias.json" '.formula["kubectl"] | join(",")' kubernetes-cli
assert_json "python → python@3.14" "${FIX}/alias.json" '.formula["python"] | join(",")' "python@3.14"
assert_json "terraform → hashicorp/tap/terraform (receipt-only keg)" "${FIX}/alias.json" '.formula["terraform"] | join(",")' hashicorp/tap/terraform
assert_json "buildkite/buildkite/bk → bk@3 (tap-qualified oldname)" "${FIX}/alias.json" '.formula["buildkite/buildkite/bk"] | join(",")' "buildkite/buildkite/bk@3"
assert_json "bk → bk@3 (bare oldname)" "${FIX}/alias.json" '.formula["bk"] | join(",")' "buildkite/buildkite/bk@3"
assert_json "jurplel/tap/instant-space-switcher → instant-space-switcher" "${FIX}/alias.json" '.cask["jurplel/tap/instant-space-switcher"] | join(",")' instant-space-switcher
assert_json "every key has exactly one value" "${FIX}/alias.json" '[.formula[], .cask[]] | all(length == 1)' true

# A second `terraform` from another tap makes the short name ambiguous instead of a guess.
jq '.formulae += [{name: "terraform", full_name: "other/tap/terraform", tap: "other/tap", aliases: [], oldnames: []}]' \
  "${FIX}/info.json" > "${FIX}/info2.json"
zfn brew.zsh brew::alias_map "${FIX}/info2.json" "${FIX}/inventory.json"
assert_eq "alias_map (ambiguous) exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/alias2.json"
assert_json "terraform has two candidates" "${FIX}/alias2.json" '.formula["terraform"] | length' 2
assert_json "candidates are both taps" "${FIX}/alias2.json" '.formula["terraform"] | sort | join(",")' "hashicorp/tap/terraform,other/tap/terraform"

zfn brew.zsh brew::classify "${FIX}/inventory.json" "${FIX}/info2.json" "${HOME}/.config/new-machine/Brewfile"
assert_eq "classify (ambiguous) exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/drift.json"
assert_json "classifier reports ambiguous_alias terraform" "${FIX}/drift.json" '[.ambiguous_alias[] | .name] | index("terraform") != null' true

report
