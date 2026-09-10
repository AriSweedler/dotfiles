#!/usr/bin/env bash
# tap-info answers are cached per tap keyed on the tap checkout's git HEAD: a second run does
# not ask brew again, a new HEAD does, and a tap dir that is not a git checkout is never cached.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
TAP_DIR="${BREW_SHIM_FIXTURE}/prefix/Library/Taps/hashicorp/homebrew-tap"
CACHE_DIR="${NEW_MACHINE_STATE_DIR}/cache/tap-info"

git_tap() { git -C "${TAP_DIR}" -c user.name=t -c user.email=t@t "$@" > /dev/null 2>&1; }
tapinfo_calls() { grep -c "^tap-info --json $1\$" "${BREW_SHIM_LOG_DIR}/brew.log" || true; }
check_drift() { bump_now_secs 60; nm check --only brew,brew_drift --json; out_json > /dev/null; }

git_tap init -q
git_tap commit -q --allow-empty -m one

check_drift
assert_eq "first run asks brew for hashicorp/tap" 1 "$(tapinfo_calls hashicorp/tap)"
assert_eq "first run asks brew for a non-git tap" 1 "$(tapinfo_calls jurplel/tap)"
assert_eq "one cache file for the git tap" 1 "$(find "${CACHE_DIR}" -name 'hashicorp--tap.*.json' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no cache file for the non-git tap" 0 "$(find "${CACHE_DIR}" -name 'jurplel--tap.*.json' 2>/dev/null | wc -l | tr -d ' ')"

check_drift
assert_eq "second run served hashicorp/tap from cache" 1 "$(tapinfo_calls hashicorp/tap)"
assert_eq "second run fetched the non-git tap again" 2 "$(tapinfo_calls jurplel/tap)"
assert_eq "cached run still sees the spacectl orphan" 1 "$(jq -r '.brew.orphan_keg | length' "${FIX}/out.json")"

git_tap commit -q --allow-empty -m two
check_drift
assert_eq "new HEAD refetches" 2 "$(tapinfo_calls hashicorp/tap)"
assert_eq "old cache file replaced, not accumulated" 1 "$(find "${CACHE_DIR}" -name 'hashicorp--tap.*.json' 2>/dev/null | wc -l | tr -d ' ')"
assert_no_mutation "cache is read-only toward brew"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
