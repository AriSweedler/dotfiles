#!/usr/bin/env bash
# The drift classifier over the hand-written drift fixture: exact counts per kind, aliases,
# orphans, duplicates, declared orphans, case-insensitive vscode ids, ignores and includes.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
P="${BREW_SHIM_FIXTURE}"
G="${HOME}/.config/new-machine/Brewfile"

snapshot() {
  zfn brew.zsh brew::inventory
  assert_eq "inventory exits 0" 0 "${RC}"
  printf '%s\n' "${OUT}" > "${FIX}/inventory.json"
  zfn brew.zsh brew::info_installed
  assert_eq "info_installed exits 0" 0 "${RC}"
  printf '%s\n' "${OUT}" > "${FIX}/info.json"
}

# classify <label> [local Brewfile] [global ignore] [local ignore] [previous] → $FIX/drift.json
classify() {
  local label="$1"; shift
  zfn brew.zsh brew::classify "${FIX}/inventory.json" "${FIX}/info.json" "${G}" "$@"
  assert_eq "classify (${label}) exits 0" 0 "${RC}"
  printf '%s\n' "${OUT}" > "${FIX}/drift.json"
}
undeclared_count() { jq -r --arg k "$1" '[.undeclared[] | select(.kind==$k)] | length' "${FIX}/drift.json"; }
is_undeclared() { jq -r --arg k "$1" --arg n "$2" '[.undeclared[] | select(.kind==$k and .name==$n)] | length > 0' "${FIX}/drift.json"; }

snapshot
classify "empty local/ignores"
assert_eq "undeclared formulae: 4" 4 "$(undeclared_count formula)"
assert_eq "undeclared casks: 2" 2 "$(undeclared_count cask)"
assert_eq "undeclared taps: 4" 4 "$(undeclared_count tap)"
assert_eq "undeclared vscode: 2" 2 "$(undeclared_count vscode)"
assert_eq "kubernetes-cli satisfied via alias kubectl" false "$(is_undeclared formula kubernetes-cli)"
assert_eq "hashicorp/tap/terraform satisfied via keg name" false "$(is_undeclared formula hashicorp/tap/terraform)"
assert_eq "python@3.14 (dependency) never appears" false "$(is_undeclared formula python@3.14)"
assert_eq "python@3.10 is undeclared" true "$(is_undeclared formula python@3.10)"
assert_eq "bk@3 undeclared under its full name" true "$(is_undeclared formula buildkite/buildkite/bk@3)"
assert_json "orphan_keg == [spacectl]" "${FIX}/drift.json" '[.orphan_keg[] | .name] | join(",")' spacelift-io/spacelift/spacectl
assert_contains "orphan hint names the cask" "$(jq -r '.orphan_keg[0].hint' "${FIX}/drift.json")" "now ships cask"
assert_json "spacectl is not also undeclared" "${FIX}/drift.json" '[.undeclared[] | select(.name | endswith("spacectl"))] | length' 0
assert_json "every undeclared item is new on the first run" "${FIX}/drift.json" '.undeclared | all(.new == true)' true
assert_json "counts.undeclared" "${FIX}/drift.json" '.counts.undeclared' 12
assert_json "no duplicates" "${FIX}/drift.json" '.duplicate|length' 0
assert_json "no declared orphans" "${FIX}/drift.json" '.declared_orphan|length' 0

classify "local aws" "${P}/Brewfile.local.aws"
assert_eq "local tier declaring one formula → 3 undeclared formulae" 3 "$(undeclared_count formula)"

classify "local dup" "${P}/Brewfile.local.dup"
assert_json "jq declared twice in one tier → duplicate" "${FIX}/drift.json" '[.duplicate[] | .name] | index("jq") != null' true

classify "local kubernetes-cli" "${P}/Brewfile.local.kubernetes-cli"
assert_json "kubectl (global) + kubernetes-cli (local) → duplicate by canon" "${FIX}/drift.json" '[.duplicate[] | .name] | index("kubernetes-cli") != null' true
assert_json "duplicate names both tiers" "${FIX}/drift.json" '.duplicate[] | select(.name=="kubernetes-cli") | .tiers | sort | join(",")' "global,local"

classify "local orphan" "${P}/Brewfile.local.orphan"
assert_json "declared orphan detected" "${FIX}/drift.json" '[.declared_orphan[] | .name] | join(",")' spacelift-io/spacelift/spacectl

classify "local vscode-case" "${P}/Brewfile.local.vscode-case"
assert_eq "vscode \"Golang.Go\" satisfies installed golang.go" false "$(is_undeclared vscode golang.go)"
assert_eq "undeclared vscode: 1" 1 "$(undeclared_count vscode)"

world_ignore local include
classify "include-declared company" "" "" "${ARI_DOTFILES_LOCAL_DIR}/Brewfile.ignore"
assert_json "bk@3 ignored via the company Brewfile" "${FIX}/drift.json" '[.ignored[] | .name] | index("buildkite/buildkite/bk@3") != null' true
assert_json "gh ignored via the company Brewfile" "${FIX}/drift.json" '[.ignored[] | .name] | index("gh") != null' true
assert_json "tap buildkite/buildkite ignored via the company Brewfile" "${FIX}/drift.json" '[.ignored[] | select(.kind=="tap") | .name] | index("buildkite/buildkite") != null' true
assert_contains "via names the include path" "$(jq -r '.ignored[] | select(.name=="gh") | .via' "${FIX}/drift.json")" "${FIX}/brew/company.Brewfile"
assert_eq "undeclared formulae with the include: 2" 2 "$(undeclared_count formula)"
assert_json "no include_declared_missing" "${FIX}/drift.json" '.include_declared_missing|length' 0

world_ignore global stale
classify "stale ignore" "" "${HOME}/.config/new-machine/Brewfile.ignore"
assert_json "formula nosuch → unresolvable_ignore" "${FIX}/drift.json" '[.unresolvable_ignore[] | .name] | join(",")' nosuch

# An ignore naming an installed dependency-only keg resolves (it is installed) without ever
# matching a drift candidate.
printf 'formula python@3.14   # dependency-only keg\n' > "${HOME}/.config/new-machine/Brewfile.ignore"
classify "dependency-only ignore" "" "${HOME}/.config/new-machine/Brewfile.ignore"
assert_json "dependency-only keg ignore is not unresolvable" "${FIX}/drift.json" '.unresolvable_ignore | length' 0
assert_json "dependency-only keg ignore matches no candidate" "${FIX}/drift.json" '[.ignored[] | select(.name == "python@3.14")] | length' 0

printf '%s\n' "include-declared ${FIX}/brew/no-such-company.Brewfile   # moved checkout" > "${ARI_DOTFILES_LOCAL_DIR}/Brewfile.ignore"
classify "include path missing" "" "" "${ARI_DOTFILES_LOCAL_DIR}/Brewfile.ignore"
assert_json "include_declared_missing names the path" "${FIX}/drift.json" '.include_declared_missing | length' 1
assert_contains "include_declared_missing carries the path" "$(jq -c '.include_declared_missing' "${FIX}/drift.json")" "no-such-company.Brewfile"
assert_eq "company items are back in undeclared (formulae: 4)" 4 "$(undeclared_count formula)"
assert_eq "gh undeclared again" true "$(is_undeclared formula gh)"

if [[ -d "${TESTS_DIR}/fixtures/this-machine" ]]; then
  world_use_fixture this-machine
  cp "${REPO_DIR}/Brewfile" "${G}"
  snapshot
  classify "this-machine + shared Brewfile"
  for name in kubernetes-cli hashicorp/tap/terraform python@3.14; do
    assert_eq "this-machine: ${name} not undeclared" false "$(is_undeclared formula "${name}")"
  done
else
  printf '  skip this-machine fixture absent (run: zsh tests/capture-fixtures.zsh)\n'
fi

report
