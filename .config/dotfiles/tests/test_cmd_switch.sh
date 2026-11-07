#!/usr/bin/env bash
# dotfiles switch: refuses the bare layout; locks the local flake's shared input at the clone's
# HEAD, commits a moved lock in the local tier (not with --no-commit), names uncommitted nix
# changes; --build builds without sudo, the default switches through sudo, --dry-run changes
# nothing; the host is ARI_DOTFILES_NIX_HOST or the flake's only one.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
FLAKE="${XDG_DATA_HOME}/dotfiles/nix"
mkdir -p "${FLAKE}"
printf '{ }\n' > "${FLAKE}/flake.nix"
printf 'old\n' > "${FLAKE}/flake.lock"
ldf_git add "${FLAKE}/flake.nix" "${FLAKE}/flake.lock"
ldf_git -c core.hooksPath=/dev/null commit -q -m "local flake"

# ── the bare layout: no git flake to lock ──
nm switch --build
assert_eq "bare layout: usage exit" 64 "${RC}"
assert_contains "bare layout: names the plain clone" "${ERR}" "plain clone"
assert_eq "bare layout: nix never called" "" "$(shim_log nix)"

# ── the plain clone ──
git clone -q "${ARI_DOTFILES_DF_GIT_DIR}" "${HOME}/dotfiles"
export ARI_DOTFILES_DF_GIT_DIR="${HOME}/dotfiles/.git"
REV="$(git -C "${HOME}/dotfiles" rev-parse HEAD)"
INPUT="git+file://${HOME}/dotfiles?dir=.config/dotfiles/nix&rev=${REV}"

nm switch --dry-run
assert_eq "dry-run: exit 0" 0 "${RC}"
assert_contains "dry-run: prints the lock" "${OUT}${ERR}" "would run: nix flake lock --override-input dotfiles '${INPUT}'"
assert_contains "dry-run: prints the switch" "${OUT}${ERR}" "darwin-rebuild switch --flake ${FLAKE}#testhost"
assert_eq "dry-run: the lock is untouched" old "$(cat "${FLAKE}/flake.lock")"
assert_eq "dry-run: sudo never called" "" "$(shim_log sudo)"

nm switch --build
assert_eq "build: exit 0" 0 "${RC}"
assert_eq "build: the lock holds the clone's HEAD" "${INPUT}" "$(cat "${FLAKE}/flake.lock")"
assert_eq "build: the moved lock is committed" "nix: lock the shared flake at ${REV:0:7}" "$(ldf_git log -1 --format=%s)"
assert_contains "build: builds the host's system" "$(shim_log nix)" "build path:${FLAKE}#darwinConfigurations.testhost.system --no-link --print-out-paths"
assert_contains "build: prints the store path" "${OUT}" "/nix/store/00000000000000000000000000000000-darwin-system"
assert_eq "build: sudo never called" "" "$(shim_log sudo)"

commits_before="$(ldf_git rev-list --count HEAD)"
nm switch
assert_eq "switch: exit 0" 0 "${RC}"
assert_eq "switch: an unmoved lock commits nothing" "${commits_before}" "$(ldf_git rev-list --count HEAD)"
assert_eq "switch: darwin-rebuild through sudo" "/run/current-system/sw/bin/darwin-rebuild switch --flake ${FLAKE}#testhost" "$(shim_log sudo)"

# An uncommitted nix change is named, and the lock still takes HEAD.
mkdir -p "${HOME}/dotfiles/.config/dotfiles/nix"
printf '{ }\n' > "${HOME}/dotfiles/.config/dotfiles/nix/new.nix"
git -C "${HOME}/dotfiles" add .config/dotfiles/nix/new.nix
git -C "${HOME}/dotfiles" -c core.hooksPath=/dev/null commit -q -m "nix: new"
printf '# edit\n' >> "${HOME}/dotfiles/.config/dotfiles/nix/new.nix"
REV="$(git -C "${HOME}/dotfiles" rev-parse HEAD)"
nm switch --build --no-commit
assert_eq "dirty nix: exit 0" 0 "${RC}"
assert_contains "dirty nix: names the path" "${ERR}" ".config/dotfiles/nix/new.nix"
assert_contains "dirty nix: the lock takes HEAD" "$(cat "${FLAKE}/flake.lock")" "rev=${REV}"
assert_eq "--no-commit: the moved lock stays uncommitted" " M share/dotfiles/nix/flake.lock" "$(ldf_git status --short -- "${FLAKE}/flake.lock")"
ldf_git checkout -q -- "${FLAKE}/flake.lock"

# ── the host ──
NIX_SHIM_HOSTS=$'personal\nwork' nm switch --build
assert_eq "two hosts: usage exit" 64 "${RC}"
assert_contains "two hosts: names them" "${ERR}" "hosts='personal, work'"
ARI_DOTFILES_NIX_HOST=work NIX_SHIM_HOSTS=$'personal\nwork' nm switch --build
assert_eq "ARI_DOTFILES_NIX_HOST: exit 0" 0 "${RC}"
assert_contains "ARI_DOTFILES_NIX_HOST: builds that host" "$(shim_log nix)" "#darwinConfigurations.work.system"

# ── failures ──
NIX_SHIM_FAIL="flake lock" nm switch --build
assert_eq "lock fails: exit 1" 1 "${RC}"
assert_contains "lock fails: says so" "${ERR}" "locking the shared input failed"

report
