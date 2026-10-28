#!/usr/bin/env bash
# `dotfiles machine-name` and the machine_name step: one local-tier file is the one source of
# truth; the verb prints only the name, sets and commits it, refuses a bad one; the step names a
# nameless machine at random and keeps an existing name.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
name_file="${XDG_DATA_HOME}/dotfiles/machine-name"

nm machine-name
assert_eq "no name yet: exit 1" 1 "${RC}"
assert_eq "no name yet: nothing on stdout" "" "${OUT}"
assert_contains "no name yet: says how to fix it" "${ERR}" "apply machine_name"

nm apply machine_name
assert_eq "apply names the machine: exit 0" 0 "${RC}"
assert_file "apply wrote the name file" "${name_file}"
first="$(tr -d '[:space:]' < "${name_file}")"
if [[ "${first}" =~ ^[a-z]+-[a-z]+$ ]]; then pass "apply wrote an adjective-noun name"
else fail "apply wrote an adjective-noun name" "name='${first}'"; fi

nm apply machine_name
assert_eq "apply again keeps the name" "${first}" "$(tr -d '[:space:]' < "${name_file}")"

nm machine-name
assert_eq "read: exit 0" 0 "${RC}"
assert_eq "read: stdout is the name alone" "${first}" "${OUT}"

nm machine-name 'two words'
assert_eq "an invalid name: exit 64" 64 "${RC}"
assert_eq "an invalid name changes nothing" "${first}" "$(tr -d '[:space:]' < "${name_file}")"

nm machine-name personal
assert_eq "set: exit 0" 0 "${RC}"
assert_eq "set: the file holds the name" "personal" "$(cat "${name_file}")"
assert_eq "set: committed in the local tier" "machine-name: personal" "$(ldf_git log -1 --format=%s)"

nm machine-name personal
assert_eq "set to the same name: exit 0" 0 "${RC}"
assert_contains "set to the same name: no change" "${OUT}" "no change"

printf 'hand-edited\n' > "${name_file}"
nm machine-name
assert_eq "an edited file is the name" "hand-edited" "${OUT}"

nm machine-name --no-commit
assert_eq "--no-commit without NAME: exit 64" 64 "${RC}"
nm machine-name renamed --no-commit
assert_eq "--no-commit: set" "renamed" "$(cat "${name_file}")"
assert_eq "--no-commit: not committed" "machine-name: personal" "$(ldf_git log -1 --format=%s)"

printf 'not one word\n' > "${name_file}"
nm machine-name
assert_eq "a malformed file: exit 1" 1 "${RC}"
nm check --only machine_name --json
assert_json "a malformed file fails the step" "$(out_json)" '.steps[0].reason' name_malformed

report
