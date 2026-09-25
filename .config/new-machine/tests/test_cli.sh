#!/usr/bin/env bash
# CLI surface: syntax, help, usage errors, `steps`, `check --json` shape, the compat shim.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

for f in "${REPO_DIR}/bin/new-machine" "${REPO_DIR}"/lib/*.zsh; do
  if zsh -n "${f}" 2> "${FIX}/syntax.err"; then pass "zsh -n $(basename "${f}")"
  else fail "zsh -n $(basename "${f}")" "$(cat "${FIX}/syntax.err")"; fi
done

nm --help
assert_eq "--help exits 0" 0 "${RC}"
for sub in setup check apply verify steps brew test; do
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
names=(brew brew_pkgs brew_drift dotfiles_repo local_dotfiles_repo bob_neovim claude terminal_nerdfont karabiner raycast_sync claude_notifications claude_skills chrome_exoskeleton plugged dotfiles_jobs)
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

nm_run "${HOME}/.config/new-machine/bin/setup-new-machine" --help
assert_eq "setup-new-machine --help works through the symlinked \$0" 0 "${RC}"

report
