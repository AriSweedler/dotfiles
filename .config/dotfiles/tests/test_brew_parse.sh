#!/usr/bin/env bash
# brew::parse_bundle_check over the captured `brew bundle check` transcripts.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
P="${BREW_SHIM_FIXTURE}"

# parse <variant> [declared_global.json] [declared_local.json] → $FIX/parsed.json
parse() {
  local variant="$1"; shift
  zfn brew.zsh brew::parse_bundle_check "${P}/bundle_check.${variant}.out" "$(cat "${P}/bundle_check.${variant}.rc")" "$@"
  assert_eq "parse ${variant} exits 0" 0 "${RC}"
  printf '%s\n' "${OUT}" > "${FIX}/parsed.json"
}

parse tap
assert_json "tap: one item" "${FIX}/parsed.json" '.items|length' 1
assert_json "tap: kind" "${FIX}/parsed.json" '.items[0].kind' tap
assert_json "tap: name" "${FIX}/parsed.json" '.items[0].name' homebrew/autoupdate
assert_json "tap: problem" "${FIX}/parsed.json" '.items[0].problem' "needs to be tapped"
assert_json "tap: nothing unparsed" "${FIX}/parsed.json" '.unparsed' false

parse mixed
assert_json "mixed: five items" "${FIX}/parsed.json" '.items|length' 5
assert_json "mixed: kinds" "${FIX}/parsed.json" '[.items[].kind] | sort | join(",")' "cask,cask,formula,tap,vscode"
assert_json "mixed: VSCode Extension → vscode" "${FIX}/parsed.json" '.items[] | select(.kind=="vscode") | .name' nosuch.extension-zzz
assert_json "mixed: formula problem" "${FIX}/parsed.json" '.items[] | select(.name=="cowsay") | .problem' "needs to be installed"
assert_json "mixed: bare cask token kept" "${FIX}/parsed.json" '[.items[] | select(.kind=="cask") | .name] | sort | join(",")' "nosuchcask-zzz,spacectl"
assert_json "mixed: nothing unparsed" "${FIX}/parsed.json" '.unparsed' false

parse unlinked
assert_json "unlinked: problem conflict" "${FIX}/parsed.json" '.items[0].problem' conflict
assert_json "unlinked: name" "${FIX}/parsed.json" '.items[0].name' jq
assert_json "unlinked: hint" "${FIX}/parsed.json" '.items[0].hint' "duplicate declaration with differing options"

parse satisfied
assert_json "satisfied: no items" "${FIX}/parsed.json" '.items|length' 0
assert_json "satisfied: nothing unparsed" "${FIX}/parsed.json" '.unparsed' false

parse garbage
assert_json "garbage: unparsed" "${FIX}/parsed.json" '.unparsed' true
assert_json "garbage: the line is quoted" "${FIX}/parsed.json" '.unparsed_lines[0]' "→ Something odd happened to foo."

# Tier attribution: bundle check prints casks as bare tokens; a declared tap-qualified cask matches by suffix.
zfn brew.zsh brew::declared "${P}/Brewfile.global"
assert_eq "declared(global) exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/declared.global.json"
printf '%s\n' 'cask "spacelift-io/spacelift/spacectl"' > "${FIX}/Brewfile.local"
zfn brew.zsh brew::declared "${FIX}/Brewfile.local"
assert_eq "declared(local) exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/declared.local.json"
parse mixed "${FIX}/declared.global.json" "${FIX}/declared.local.json"
assert_json "→ Cask spacectl attributed to local by suffix" "${FIX}/parsed.json" '.items[] | select(.name=="spacectl") | .tier' local
assert_json "tap attributed to global" "${FIX}/parsed.json" '.items[] | select(.name=="homebrew/autoupdate") | .tier' global
assert_json "undeclared item has tier ?" "${FIX}/parsed.json" '.items[] | select(.name=="cowsay") | .tier' "?"

report
