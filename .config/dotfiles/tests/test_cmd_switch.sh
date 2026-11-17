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
export ARI_DOTFILES_NIX_FLAKE="${XDG_DATA_HOME}/dotfiles/nix"   # the real default; the world points it elsewhere
FLAKE="${ARI_DOTFILES_NIX_FLAKE}"
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

# ── --remote: a NixOS host deployed from here by its recipe ──
nm switch --execute
assert_eq "--execute alone: usage exit" 64 "${RC}"
nm switch --remote web
assert_eq "no recipe: exit 64" 64 "${RC}"
assert_contains "no recipe: names the file" "${ERR}" "${XDG_DATA_HOME}/dotfiles/remotes/web"

# The host flake (its own repo, a submodule of a homelab repo), each with a bare origin.
HL="${FIX}/homelab"
git init -q --bare --initial-branch=main "${FIX}/web.git"
git clone -q "${FIX}/web.git" "${FIX}/web-seed" 2>/dev/null
printf '{"nodes":{"dotfiles":{"locked":{"rev":"old"}}}}\n' > "${FIX}/web-seed/flake.lock"
git -C "${FIX}/web-seed" add flake.lock
git -C "${FIX}/web-seed" -c core.hooksPath=/dev/null commit -q -m "web flake"
git -C "${FIX}/web-seed" push -q origin HEAD:main
git init -q --bare --initial-branch=main "${FIX}/homelab.git"
git clone -q "${FIX}/homelab.git" "${HL}" 2>/dev/null
git -C "${HL}" -c protocol.file.allow=always submodule add -q "${FIX}/web.git" hosts/web
git -C "${HL}" -c core.hooksPath=/dev/null commit -q -m "add hosts/web"
git -C "${HL}" push -q origin HEAD:main
FLAKE_WEB="${HL}/hosts/web"

# ssh logs its call; deploy and check leave markers in the repo they run in.
cat > "${FIX}/shims/ssh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${BREW_SHIM_LOG_DIR}/ssh.log"
EOF
chmod +x "${FIX}/shims/ssh"
mkdir -p "${XDG_DATA_HOME}/dotfiles/remotes"
RECIPE="${XDG_DATA_HOME}/dotfiles/remotes/web"
printf 'flake=%s\nrepo=%s\n' "${FLAKE_WEB}" "${HL}" > "${RECIPE}"
nm switch --remote web
assert_eq "recipe without deploy: exit 64" 64 "${RC}"
assert_contains "recipe without deploy: names the key" "${ERR}" "lacks deploy"
printf '# web\nflake=%s\nrepo=%s\ndeploy=touch deployed\ncheck=touch checked\nssh=me@192.0.2.10\n' "${FLAKE_WEB}" "${HL}" > "${RECIPE}"

# Unpushed shared commits: refused, after the dry-run banner.
nm switch --remote web
assert_eq "unpushed: exit 1" 1 "${RC}"
assert_contains "unpushed: the dry-run banner" "${ERR}" "DRY RUN"
assert_contains "unpushed: names the fix" "${ERR}" "fix='dotfiles push'"
assert_not_contains "unpushed: nix flake update never ran" "$(shim_log nix)" "flake update dotfiles"

git -C "${HOME}/dotfiles" push -q origin HEAD:main
PUSHED="$(git -C "${HOME}/dotfiles" rev-parse HEAD)"
export NIX_SHIM_UPDATE_REV="${PUSHED}"

# The dry run: the banner first, every step printed, nothing changed.
nm switch --remote web
assert_eq "dry run: exit 0" 0 "${RC}"
assert_contains "dry run: the banner says how to run it" "${ERR}" "dotfiles switch --remote web --execute"
assert_eq "dry run: the banner leads" "!!!!" "$(printf '%s\n' "${ERR}" | head -1 | cut -c1-4)"
assert_contains "dry run: prints the lock update" "${ERR}" "nix flake update dotfiles --refresh --flake ${FLAKE_WEB}"
assert_contains "dry run: prints the deploy" "${ERR}" "touch deployed"
assert_contains "dry run: prints the ssh" "${ERR}" "me@192.0.2.10"
assert_contains "dry run: ends with the reminder" "${ERR}" "that was a dry run"
assert_eq "dry run: the lock is untouched" old "$(jq -r .nodes.dotfiles.locked.rev "${FLAKE_WEB}/flake.lock")"
assert_eq "dry run: no deploy" no "$([[ -e "${HL}/deployed" ]] && echo yes || echo no)"
assert_eq "dry run: no ssh" "" "$(shim_log ssh)"

# --execute: lock, commit and push the flake, bump the pointer, pull, deploy, check, reload.
nm switch --remote web --execute
assert_eq "execute: exit 0" 0 "${RC}"
assert_not_contains "execute: no banner" "${ERR}" "DRY RUN"
assert_eq "execute: the lock is at the pushed commit" "${PUSHED}" "$(jq -r .nodes.dotfiles.locked.rev "${FLAKE_WEB}/flake.lock")"
assert_eq "execute: the lock is committed" "dotfiles: bump to ${PUSHED:0:7}" "$(git -C "${FLAKE_WEB}" log -1 --format=%s)"
assert_eq "execute: the flake is pushed" "$(git -C "${FLAKE_WEB}" rev-parse HEAD)" "$(git -C "${FIX}/web.git" rev-parse main)"
assert_eq "execute: the pointer is committed" "hosts/web: bump (dotfiles ${PUSHED:0:7})" "$(git -C "${HL}" log -1 --format=%s)"
assert_eq "execute: the pointer is pushed" "$(git -C "${HL}" rev-parse HEAD)" "$(git -C "${FIX}/homelab.git" rev-parse main)"
assert_eq "execute: deployed in the repo" yes "$([[ -e "${HL}/deployed" ]] && echo yes || echo no)"
assert_eq "execute: checked in the repo" yes "$([[ -e "${HL}/checked" ]] && echo yes || echo no)"
SSH_CALLS=()
while IFS= read -r line; do SSH_CALLS+=("${line}"); done < <(shim_log ssh)
assert_eq "execute: ssh twice" 2 "${#SSH_CALLS[@]}"
assert_contains "execute: the pull comes first" "${SSH_CALLS[0]:-}" "dotfiles pull"
assert_contains "execute: then the tmux reload" "${SSH_CALLS[1]:-}" "tmux source-file"
assert_contains "execute: says what runs" "${ERR}" "web runs the shared tier at ${PUSHED:0:7}"

# Again: the lock already holds the commit, so nothing is committed.
HL_HEAD="$(git -C "${HL}" rev-parse HEAD)"
nm switch --remote web --execute
assert_eq "again: exit 0" 0 "${RC}"
assert_contains "again: says the lock is current" "${ERR}" "already locks this commit"
assert_eq "again: no new pointer commit" "${HL_HEAD}" "$(git -C "${HL}" rev-parse HEAD)"

# A lock that misses the pushed commit (nix's cached ref) stops before any commit.
NIX_SHIM_UPDATE_REV=0000000 nm switch --remote web --execute
assert_eq "stale lock: exit 1" 1 "${RC}"
assert_contains "stale lock: says so" "${ERR}" "did not land on the pushed commit"
git -C "${FLAKE_WEB}" checkout -q -- flake.lock
unset NIX_SHIM_UPDATE_REV

report
