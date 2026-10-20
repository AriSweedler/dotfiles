#!/usr/bin/env bash
# `dotfiles pull` names the steps its changes affect and runs none of them: the mapping
# (step::watches, watch::map) as a pure function of the changed paths, then a world's pull and
# dry-run, inside the 0.5 s budget and with no check run.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
LIB="${ORIG_CONFIG_DIR}/dotfiles/lib"
STEPS_DIR="${ORIG_CONFIG_DIR}/dotfiles/steps"

# map_paths STEPS_DIR < name-status lines: watch::map's lines, after the registry and its watches
# load the way a step subprocess sees the kernel (lib/*.zsh only). Fills OUT, ERR, RC.
map_paths() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -f -c '
    for f in "$1"/*.zsh; do source "$f"; done
    steps::load "$2" || exit 3
    watch::validate || exit 3
    watch::map' map "${LIB}" "$1" > "${FIX}/map.out" 2> "${FIX}/map.err" || RC=$?
  OUT="$(cat "${FIX}/map.out")"
  ERR="$(cat "${FIX}/map.err")"
}

# --- The mapping ---

map_paths "${STEPS_DIR}" < /dev/null
assert_eq "nothing changed: registry valid" 0 "${RC}"
assert_eq "nothing changed: no lines" "" "${OUT}"

map_paths "${STEPS_DIR}" <<'EOF'
M	.config/new-machine/Brewfile
EOF
assert_eq "Brewfile: both brew steps, registry order" "step brew_drift .config/new-machine/Brewfile
step brew_pkgs .config/new-machine/Brewfile" "${OUT}"

map_paths "${STEPS_DIR}" <<'EOF'
M	.config/karabiner/karabiner.ts
M	.config/claude/skills/ari-dotfiles/SKILL.md
M	.config/plugged
M	.gitmodules
EOF
assert_eq "karabiner, a skill, a submodule pointer, .gitmodules" "step dotfiles_repo .gitmodules
step claude_skills .config/claude/skills/ari-dotfiles/SKILL.md
step karabiner .config/karabiner/karabiner.ts
step plugged .config/plugged
step raycast_sync .config/karabiner/karabiner.ts" "${OUT}"

map_paths "${STEPS_DIR}" <<'EOF'
M	.config/dotfiles/steps/alttab.zsh
A	.config/dotfiles/steps/zz_new_step.zsh
D	.config/dotfiles/steps/old_step.zsh
EOF
assert_eq "step files: edited and new map to themselves, deleted is removed" "step alttab .config/dotfiles/steps/alttab.zsh
step zz_new_step .config/dotfiles/steps/zz_new_step.zsh
removed old_step .config/dotfiles/steps/old_step.zsh" "${OUT}"

map_paths "${STEPS_DIR}" <<'EOF'
M	.config/dotfiles/lib/ui.zsh
A	.config/dotfiles/cmd/brew/new.zsh
M	.config/bin/dotfiles
M	README.md
EOF
assert_eq "harness only: no step" "harness .config/dotfiles/lib/ui.zsh
harness .config/dotfiles/cmd/brew/new.zsh
harness .config/bin/dotfiles" "${OUT}"

map_paths "${STEPS_DIR}" <<'EOF'
M	.config/dotfiles/jobs/git-health/run
M	.config/raycast-snippets/snippets.json
M	.config/dotfiles/tests/test_pull.sh
EOF
assert_eq "jobs, snippets, and a test to the suites' doc rule" "step dotfiles_jobs .config/dotfiles/jobs/git-health/run
step test_suites .config/dotfiles/tests/test_pull.sh
step raycast_sync .config/raycast-snippets/snippets.json" "${OUT}"

# A watch must name a declared step, from that step's own file.
bad="${FIX}/bad-steps"
mkdir -p "${bad}"
printf 'step::declare one\nstep::watches nobody x\ncheck::one() { :; }\n' > "${bad}/one.zsh"
map_paths "${bad}" < /dev/null
assert_eq "undeclared watch: exit 3" 3 "${RC}"
assert_contains "undeclared watch: named" "${ERR}" "watch for an undeclared step | step='nobody'"
rm -f "${bad}/one.zsh"
printf 'step::declare one\ncheck::one() { :; }\n' > "${bad}/one.zsh"
printf 'step::declare two\nstep::watches one x\ncheck::two() { :; }\n' > "${bad}/two.zsh"
map_paths "${bad}" < /dev/null
assert_eq "watch from another file: exit 3" 3 "${RC}"
assert_contains "watch from another file: named" "${ERR}" "watch declared in another file | step='one' file='two.zsh'"

# --- A world's pull ---

world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
REMOTE="${FIX}/remotes/dotfiles.git"
CLONE="${FIX}/clone"
git clone -q --bare "${ARI_DOTFILES_DF_GIT_DIR}" "${REMOTE}"
df_git remote add origin "${REMOTE}"
df_git fetch -q origin
df_git branch -q --set-upstream-to=origin/main main
git clone -q "${REMOTE}" "${CLONE}"

# remote_append FILE TEXT: a line appended to FILE on origin, hooks off.
remote_append() {
  mkdir -p "${CLONE}/$(dirname "$1")"; printf '%s\n' "$2" >> "${CLONE}/$1"
  git -C "${CLONE}" add "$1" && git -C "${CLONE}" -c core.hooksPath=/dev/null commit -q -m "edit $1"
}

nm pull
assert_eq "up to date: exit 0" 0 "${RC}"
assert_eq "up to date: one line after git's" "up to date: nothing to pull" "${OUT##*$'\n'}"

remote_append .config/new-machine/Brewfile '# a pulled comment'
remote_append .config/raycast-snippets/snippets.json '[]'
git -C "${CLONE}" push -q origin main
head_before="$(df_git rev-parse HEAD)"

nm pull --dry-run
assert_eq "dry-run: exit 0" 0 "${RC}"
assert_eq "dry-run: HEAD unchanged" "${head_before}" "$(df_git rev-parse HEAD)"
assert_eq "dry-run: origin fetched" "$(git -C "${CLONE}" rev-parse HEAD)" "$(df_git rev-parse origin/main)"
assert_contains "dry-run: says would" "${OUT}" "would pull 2 changed paths"
assert_contains "dry-run: names the apply" "${OUT}" "run: dotfiles apply brew_drift brew_pkgs raycast_sync"

shim_logs_reset
nm --timing pull
assert_eq "pull: exit 0 with steps affected" 0 "${RC}"
assert_eq "pull: at origin" "$(git -C "${CLONE}" rev-parse HEAD)" "$(df_git rev-parse HEAD)"
assert_contains "pull: counts the paths" "${OUT}" "pulled 2 changed paths"
assert_contains "pull: warns per step with its paths" "${OUT}" "  brew_pkgs     .config/new-machine/Brewfile"
assert_contains "pull: raycast_sync for its snippets" "${OUT}" "  raycast_sync  .config/raycast-snippets/snippets.json"
assert_contains "pull: the one command" "${OUT}" "run: dotfiles apply brew_drift brew_pkgs raycast_sync"
assert_contains "pull: the warning says what changed, steps plural" "${OUT}" "the pull changed files 3 steps read; check this machine still matches:"
assert_contains "pull: logged as a warning" "${ERR}" "pulled changes affect steps | steps='brew_drift,brew_pkgs,raycast_sync'"
assert_no_file "pull: no init run" "${ARI_DOTFILES_STATE_DIR}/runs"
assert_no_file "pull: no init result" "${ARI_DOTFILES_STATE_DIR}/last_result.json"
assert_eq "pull: brew never called" "" "$(shim_log brew)"
took=""
[[ "${ERR}" =~ name=\'pull_changes\'\ took=\'([0-9.]+)s\' ]] && took="${BASH_REMATCH[1]}"
assert_eq "pull: the analysis was timed" 1 "$([[ -n "${took}" ]] && echo 1 || echo 0)"
assert_eq "pull: the analysis within 0.5 s (took ${took:-?}s)" 1 "$(awk -v t="${took:-9}" 'BEGIN { print (t <= 0.5) ? 1 : 0 }')"

# --- One warning: on a terminal the stdout block is it; a kept log still gets the record ---

# Fancy output (seam + fake gum) with stderr in a file: that file is a log, so the record stays.
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nexit 0\n' > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
remote_append .config/new-machine/Brewfile '# another pulled comment'
git -C "${CLONE}" push -q origin main
export ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}"
nm pull --dry-run
unset ARI_DOTFILES_UI ARI_DOTFILES_GUM
assert_eq "fancy, stderr a file: exit 0" 0 "${RC}"
assert_contains "fancy, stderr a file: the block names the apply" "$(printf '%s' "${OUT}" | /usr/bin/sed -E $'s/\x1b\\[[0-9;]*m//g')" "run: dotfiles apply brew_drift brew_pkgs"
assert_contains "fancy, stderr a file: the record is logged" "${ERR}" "pulled changes affect steps | steps='brew_drift,brew_pkgs'"

# One step: the warning in the singular (the dry run above left its pull to take first).
nm pull
remote_append .config/raycast-snippets/snippets.json ''
git -C "${CLONE}" push -q origin main
nm pull
assert_contains "one step: the warning in the singular" "${OUT}" "the pull changed files 1 step reads; check this machine still matches:"
assert_contains "one step: its apply" "${OUT}" "run: dotfiles apply raycast_sync"

# pull::is_terminal, the one switch: true only when fancy and stderr is a tty.
is_terminal_rc() {
  env -i "${HERMETIC_ENV[@]}" "$@" "${FIX}/tools/zsh" -f -c '
    for f in "$1"/lib/*.zsh; do source "$f"; done
    source "$1"/cmd/pull.zsh
    pull::is_terminal' rc "${ORIG_CONFIG_DIR}/dotfiles" 2>/dev/null && echo 0 || echo 1
}
hermetic_env
assert_eq "is_terminal: plain is not" 1 "$(is_terminal_rc ARI_DOTFILES_UI=plain)"
assert_eq "is_terminal: fancy with stderr not a tty is not" 1 \
  "$(is_terminal_rc ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}")"

report
