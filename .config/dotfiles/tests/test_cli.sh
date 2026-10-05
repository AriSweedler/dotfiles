#!/usr/bin/env bash
# CLI surface: syntax, help, usage errors, `steps`, `check --json` shape, the compat shim.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

for f in "${ORIG_CONFIG_DIR}/bin/dotfiles" "${ORIG_CONFIG_DIR}"/dotfiles/lib/*.zsh "${ORIG_CONFIG_DIR}"/dotfiles/cmd/*.zsh "${ORIG_CONFIG_DIR}"/dotfiles/steps/*.zsh; do
  if zsh -n "${f}" 2> "${FIX}/syntax.err"; then pass "zsh -n $(basename "${f}")"
  else fail "zsh -n $(basename "${f}")" "$(cat "${FIX}/syntax.err")"; fi
done

nm --help
assert_eq "--help exits 0" 0 "${RC}"
for sub in init check apply verify steps brew test; do
  assert_contains "--help lists ${sub}" "${OUT}${ERR}" "${sub}"
done

nm --no-such-flag
assert_eq "unknown flag exits 64" 64 "${RC}"
nm check --only nosuch
assert_eq "check --only nosuch exits 64" 64 "${RC}"
nm brew decree gh
assert_eq "decree without a tier flag exits 64" 64 "${RC}"

nm steps
assert_eq "steps exits 0" 0 "${RC}"
names=(brew brew_pkgs brew_drift dotfiles_repo local_dotfiles_repo ssh_key bob_neovim claude terminal_nerdfont karabiner raycast_sync claude_notifications claude_skills chrome_exoskeleton plugged dotfiles_jobs)
listed=0
for s in "${names[@]}"; do
  if grep -qE "(^|[[:space:]])${s}([[:space:]]|$)" <<< "${OUT}"; then listed=$((listed + 1)); else fail "steps lists ${s}" "${OUT}"; fi
done
assert_eq "steps lists every name" "${EXPECTED_STEPS}" "${listed}"

nm check --json
f="$(out_json)"
assert_eq "check --json prints one JSON object" 1 "$(jq -s 'map(select(type=="object")) | length' "${f}" 2>&1)"
assert_json "schema == 1" "${f}" '.schema' 1
assert_json "steps|length matches the registry" "${f}" '.steps|length' "${EXPECTED_STEPS}"

nm --help
assert_eq "--help exits 0" 0 "${RC}"
for verb in healthcheck apply steps verify brew push init jobs; do
  if grep -qE "^  ${verb}[[:space:]]+[a-z]" <<< "${OUT}"; then pass "--help lists ${verb} with a description"
  else fail "--help lists ${verb} with a description" "${OUT}"; fi
done
nm push --help
assert_eq "a verb answers --help" 0 "${RC}"
assert_contains "push --help is push's help" "${OUT}" "publish every tier"
nm --verbose --help
assert_contains "--verbose --help prints every verb's help" "${OUT}" "Pushes every submodule"
nm
assert_eq "bare dotfiles exits 0" 0 "${RC}"
assert_contains "bare dotfiles lists the verbs" "${OUT}" "Verbs"
nm help init
assert_eq "help VERB exits 0" 0 "${RC}"
assert_contains "help init is init's help" "${OUT}" "converge this machine"
nm jobs list --help
assert_contains "a sub-verb's --help is its verb's help" "${OUT}" "launchd job"
nm setup
assert_eq "setup is gone" 64 "${RC}"
nm nosuch
assert_eq "unknown verb exits 64" 64 "${RC}"

report
