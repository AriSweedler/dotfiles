#!/usr/bin/env bash
# A mirror ([mirror "<path>"] in the dev-repos manifest) is a public repo whose directory is a
# copy of one of the shared flake's packages. `dotfiles push` exports it first (mirror::export):
# the package built from the shared tier's HEAD replaces the checkout's directory and is
# committed alone; the build runs only when a watched path changed since the last export. Here
# nix is the shim, whose `build` prints NIX_SHIM_BUILD_OUT, a fake read-only store directory.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PUSH_ZSH="${ORIG_CONFIG_DIR}/dotfiles/cmd/push.zsh"

# pz SCRIPT [ARG…]: the kernel plus cmd/push.zsh in the hermetic environment, then SCRIPT (zsh);
# captures OUT, ERR, RC.
pz() {
  local script="$1"; shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c 'for f in "$1"/*.zsh(N); do source "${f}"; done; source "$2"; s="$3"; shift 3; eval "${s}"' _ \
    "${ORIG_CONFIG_DIR}/dotfiles/lib" "${PUSH_ZSH}" "${script}" "$@" > "${FIX}/pz.out" 2> "${FIX}/pz.err" || RC=$?
  OUT="$(cat "${FIX}/pz.out")"
  ERR="$(cat "${FIX}/pz.err")"
}
# export_mirror: mirror::export on the one mirror; RC is its return code, OUT its PUSH_ROWS.
export_mirror() { pz 'local -a PUSH_ROWS=(); local rc=0; mirror::export .config/mirror || rc=$?; print -rl -- "${PUSH_ROWS[@]}"; return ${rc}'; }

world_new
seed_fake_repos
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh.log"\nexit 1\n' "${BREW_SHIM_LOG_DIR}" > "${FIX}/shims/gh"
chmod +x "${FIX}/shims/gh"

MIRROR="${HOME}/.config/mirror"
BARE="${FIX}/remotes/mirror.git"
m_git() { git -C "${MIRROR}" "$@"; }
stamp() { m_git config --local --get dotfiles.mirroredRev; }
# shared_commit FILE: one more shared commit changing FILE (relative to HOME).
shared_commit() {
  mkdir -p "$(dirname "${HOME}/$1")"
  printf '%s\n' "${RANDOM}" >> "${HOME}/$1"
  df_git add "${HOME}/$1" && df_git -c core.hooksPath=/dev/null commit -q -m "change $1"
}

# The mirror: one published commit holding an old lib/, a README the export never touches.
git init -q --initial-branch=main "${MIRROR}"
mkdir -p "${MIRROR}/lib"
printf 'old\n' > "${MIRROR}/lib/a.zsh"
printf 'gone\n' > "${MIRROR}/lib/dropped.zsh"
printf 'readme\n' > "${MIRROR}/README.md"
m_git add lib README.md && m_git commit -q -m one
git init -q --bare --initial-branch=main "${BARE}"
m_git push -q "${BARE}" main
m_git fetch -q "${BARE}" main:refs/remotes/origin/main
m_git remote add origin "https://github.com/push-mirror-test/mirror.git"

world_dev_repos
printf '[mirror ".config/mirror"]\n\tpath = .config/mirror\n\turl = https://github.com/push-mirror-test/mirror.git\n\tpackage = pkg\n\twatch = .config/src .config/more\n' >> "${HOME}/.config/dotfiles/dev-repos"
df_git add "${HOME}/.config/dotfiles/dev-repos" && df_git -c core.hooksPath=/dev/null commit -q -m "manifest"
shared_commit .config/src/a.zsh

# The package, as the store holds it: read-only.
STORE="${FIX}/store/pkg"
mkdir -p "${STORE}/lib/assets"
printf 'new\n' > "${STORE}/lib/a.zsh"
printf 'png\n' > "${STORE}/lib/assets/icon.png"
chmod -R a-w "${STORE}"
export NIX_SHIM_BUILD_OUT="${STORE}"

# ── The manifest ─────────────────────────────────────────────────────────────

pz 'print -r -- "${#SUBMODULES}|${MIRRORS[*]}|${MIRROR_PACKAGE[.config/mirror]}|${MIRROR_DIR[.config/mirror]}|${MIRROR_WATCH[.config/mirror]}"'
assert_eq "manifest: a mirror is not a dev repo; package, dir (default lib) and watch are read" "0|.config/mirror|pkg|lib|.config/src .config/more" "${OUT}"

# ── First export: no stamp, so it builds ─────────────────────────────────────

HEAD1="$(df_git rev-parse HEAD)"
shim_logs_reset
export_mirror
assert_eq "first: committed (rc 0)" 0 "${RC}"
assert_contains "first: nix built the package from the shared HEAD" "$(shim_log nix)" "build git+file://${HOME}?dir=.config/dotfiles/nix&rev=${HEAD1}#pkg --no-link --print-out-paths"
assert_eq "first: the commit names the shared commit" "lib: mirror dotfiles ${HEAD1:0:7}" "$(m_git log -1 --format=%s)"
assert_eq "first: the commit carries the personal identity" "Ari Sweedler <ari@sweedler.com>" "$(m_git log -1 --format='%an <%ae>')"
assert_eq "first: the file is the package's" "new" "$(cat "${MIRROR}/lib/a.zsh")"
assert_eq "first: a subdirectory comes along" "png" "$(cat "${MIRROR}/lib/assets/icon.png")"
assert_eq "first: a file the package lacks is deleted" "D	lib/dropped.zsh" "$(m_git show --format= --name-status HEAD | grep dropped)"
assert_eq "first: only the directory is committed" "" "$(m_git show --format= --name-only HEAD | grep -v '^lib/')"
assert_eq "first: the copy is writable" "yes" "$([[ -w "${MIRROR}/lib/a.zsh" && -w "${MIRROR}/lib/assets" ]] && echo yes)"
assert_eq "first: the work tree is clean" "" "$(m_git status --porcelain)"
assert_eq "first: the stamp is the shared HEAD" "${HEAD1}" "$(stamp)"
assert_contains "first: the row" "${OUT}" "mirror mirror	exported	$(m_git rev-parse HEAD)"
COMMITS="$(m_git rev-list --count HEAD)"

# ── Nothing new in the shared tier: no build ─────────────────────────────────

shim_logs_reset
export_mirror
assert_eq "same HEAD: nothing to do (rc 2)" 2 "${RC}"
assert_eq "same HEAD: nix not called" "" "$(shim_log nix)"

# ── A shared commit outside the watched paths: no build, the stamp follows ───

shared_commit .config/elsewhere.txt
shim_logs_reset
export_mirror
assert_eq "unwatched change: nothing to do (rc 2)" 2 "${RC}"
assert_eq "unwatched change: nix not called" "" "$(shim_log nix)"
assert_eq "unwatched change: the stamp moved to HEAD" "$(df_git rev-parse HEAD)" "$(stamp)"

# ── A watched change the package does not show: a build, no commit ───────────

shared_commit .config/more/b.zsh
shim_logs_reset
export_mirror
assert_eq "watched, same package: nothing to do (rc 2)" 2 "${RC}"
assert_contains "watched, same package: nix built" "$(shim_log nix)" "#pkg"
assert_eq "watched, same package: no new commit" "${COMMITS}" "$(m_git rev-list --count HEAD)"
assert_eq "watched, same package: the stamp moved to HEAD" "$(df_git rev-parse HEAD)" "$(stamp)"

# ── A dry run: the plan, nothing built or written ────────────────────────────

shared_commit .config/src/a.zsh
STAMP="$(stamp)"
shim_logs_reset
ARI_DOTFILES_DRY_RUN=1 export_mirror
assert_eq "dry run: nothing done (rc 2)" 2 "${RC}"
assert_eq "dry run: nix not called" "" "$(shim_log nix)"
assert_contains "dry run: says what it would do" "${ERR}" "dry-run, would export | repo='.config/mirror' package='pkg' dir='lib'"
assert_contains "dry run: the row" "${OUT}" "mirror mirror	would export"
assert_eq "dry run: the stamp stays" "${STAMP}" "$(stamp)"

# ── Refusals: a build failure, a dirty directory, another branch ─────────────

NIX_SHIM_FAIL=build export_mirror
assert_eq "build failure: rc 1" 1 "${RC}"
assert_contains "build failure: says so" "${ERR}" "mirror not exported: the package did not build | repo='.config/mirror' package='pkg'"
assert_eq "build failure: the stamp stays" "${STAMP}" "$(stamp)"
assert_eq "build failure: the mirror is untouched" "" "$(m_git status --porcelain)"

printf 'edited here\n' >> "${MIRROR}/lib/a.zsh"
shim_logs_reset
export_mirror
assert_eq "dirty: rc 1" 1 "${RC}"
assert_contains "dirty: says where the change belongs" "${ERR}" "lib/ has uncommitted changes (a mirror is written in the dotfiles, never in its checkout)"
assert_eq "dirty: nix not called" "" "$(shim_log nix)"
assert_eq "dirty: the edit is kept" "edited here" "$(tail -n 1 "${MIRROR}/lib/a.zsh")"
m_git checkout -q -- lib

m_git switch -q -c side
export_mirror
assert_eq "off main: rc 1" 1 "${RC}"
assert_contains "off main: names the branch and the fix" "${ERR}" "its checkout is not on main | repo='.config/mirror' branch='side' fix='git -C ~/.config/mirror switch main'"
m_git switch -q main

# ── A changed package: the second export, then `dotfiles push --dry-run` ─────

chmod -R u+w "${STORE}"
printf 'newer\n' > "${STORE}/lib/a.zsh"
chmod -R a-w "${STORE}"
export_mirror
assert_eq "changed package: committed (rc 0)" 0 "${RC}"
assert_eq "changed package: the file follows" "newer" "$(cat "${MIRROR}/lib/a.zsh")"
assert_eq "changed package: one more commit" "$(( COMMITS + 1 ))" "$(m_git rev-list --count HEAD)"

shim_logs_reset
nm push --dry-run --submodules
assert_eq "push --dry-run: exit 0" 0 "${RC}"
assert_contains "push --dry-run: the mirror would be pushed like a dev repo" "${ERR}" "dry-run, would push | repo='.config/mirror' branch='main'"
assert_not_contains "push --dry-run: a mirror has no pointer to bump" "${ERR}" "would bump"
assert_eq "push --dry-run: nix not called (exported already)" "" "$(shim_log nix)"

# ── No checkout: silent ──────────────────────────────────────────────────────

mv "${MIRROR}" "${FIX}/mirror.away"
export_mirror
assert_eq "no checkout: nothing to do (rc 2)" 2 "${RC}"
assert_eq "no checkout: no words" "" "${ERR}"
nm push --dry-run --submodules
assert_eq "no checkout: push exits 0" 0 "${RC}"
assert_not_contains "no checkout: push does not mention it" "${ERR}" ".config/mirror"

chmod -R u+w "${STORE}"
report
