#!/usr/bin/env bash
# The registry helpers in lib.sh: what the suite's "every step" properties compare against is
# the checkout's own registry, and assert_steps_are_registry refuses a missing, doubled or
# unknown step.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
registry_load

files="$(for s in "${ORIG_CONFIG_DIR}"/dotfiles/steps/*.zsh; do basename "${s}" .zsh; done | names_csv)"
assert_eq "registry_steps is the step files" "${files}" "$(registry_steps | names_csv)"
assert_eq "registry_step_count counts the step files" "$(registry_steps | wc -l | tr -d ' ')" "$(registry_step_count)"
groups="$(harness_var STEP_GROUPS)"
assert_eq "harness_var reads the kernel's groups" true "$([[ -n "${groups}" ]] && echo true || echo false)"
# shellcheck disable=SC2086  # the groups are words
grouped="$(for g in ${groups}; do registry_steps_in_group "${g}"; done | names_csv)"
assert_eq "the groups partition the registry" "${files}" "${grouped}"
assert_eq "an unknown group has no steps" "" "$(registry_steps_in_group nosuch)"
assert_eq "names_json keeps every name" "$(registry_step_count)" "$(registry_steps | names_json | jq length)"

registry_steps | jq -R '{step: .}' | jq -s '{steps: .}' > "${FIX}/full.json"
jq 'del(.steps[0])' "${FIX}/full.json" > "${FIX}/missing.json"
jq '.steps += [.steps[0]]' "${FIX}/full.json" > "${FIX}/doubled.json"
jq '.steps += [{step: "no_such_step"}]' "${FIX}/full.json" > "${FIX}/extra.json"
# Each probe runs in a subshell so its verdict does not count toward this file's totals.
verdict_of() { ( PASS=0; FAIL=0; assert_steps_are_registry probe "$1" > /dev/null 2>&1; printf '%s' "${FAIL}" ); }
assert_eq "a summary of every step passes" 0 "$(verdict_of "${FIX}/full.json")"
assert_eq "a missing step fails" 1 "$(verdict_of "${FIX}/missing.json")"
assert_eq "a doubled step fails" 1 "$(verdict_of "${FIX}/doubled.json")"
assert_eq "an unregistered step fails" 1 "$(verdict_of "${FIX}/extra.json")"
assert_eq "no summary fails" 1 "$(verdict_of "${FIX}/no-such.json")"

assert_eq "harness_var reads the kernel's CLI_NAME (the entrypoint's name)" "$(basename "${ORIG_CONFIG_DIR}/bin/dotfiles")" "$(harness_var CLI_NAME)"

report
