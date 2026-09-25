#!/usr/bin/env bash
# The harness itself: HOME and PATH resolve inside the world, and sourcing a lib has no effect.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

zfn env.zsh env_probe
assert_eq "env_probe exits 0" 0 "${RC}"
f="$(out_json)"
probe_home="$(jq -r .home "${f}")"
assert_eq "probe HOME is the fake home" "${HOME}" "${probe_home}"
assert_not_contains "probe HOME is not the real home" "${probe_home}" "${ORIG_HOME}"
assert_eq "command -v brew is the shim" "${FIX}/shims/brew" "$(jq -r .brew_on_path "${f}")"
assert_eq "NEW_MACHINE_BREW is the shim" "${FIX}/shims/brew" "$(jq -r .brew "${f}")"
probe_path="$(jq -r .path "${f}")"
assert_eq "PATH starts with the shim dir" "${FIX}/shims" "${probe_path%%:*}"
assert_not_contains "PATH has no real-machine entries" "${probe_path}" "/opt/homebrew"

# Sourcing a lib may create nothing anywhere in the world, not only under HOME, and runs from a
# throwaway cwd so a relative write would show up too.
mkdir -p "${FIX}/cwd"
snapshot() { find "${FIX}" -mindepth 1 -not -name 'source.out' -not -name 'source.err' | sort; }
before="$(snapshot)"
hermetic_env
for lib in "${ORIG_CONFIG_DIR}"/dotfiles/lib/*.zsh "${ORIG_CONFIG_DIR}"/dotfiles/cmd/brew/*.zsh "${ORIG_CONFIG_DIR}"/dotfiles/cmd/verify/*.zsh; do
  name="$(basename "${lib}")"
  if env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c 'cd "$2" && source "$1"' _ "${lib}" "${FIX}/cwd" \
       > "${FIX}/source.out" 2> "${FIX}/source.err"; then pass "source ${name} exits 0"
  else fail "source ${name} exits 0" "$(cat "${FIX}/source.err")"; fi
  assert_eq "source ${name} prints nothing" "" "$(cat "${FIX}/source.out")"
done
after="$(snapshot)"
assert_eq "sourcing the libs created no files" "${before}" "${after}"

report
