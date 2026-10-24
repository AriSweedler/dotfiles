#!/usr/bin/env bash
# Check speed, part 2: the checks of a group run side by side and a run reads exactly as a serial
# one (stdout, stderr, run.log, summary.json); claude_skills is cached on its links and misses
# when one changes; bob_neovim and raycast_sync never cache behind a seam (a shim, a bindings
# command), whose state the fingerprint cannot see.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mask() { /usr/bin/sed -E 's/\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z\]/[TS]/g; s/[0-9]{8}T[0-9]{6}/RUNID/g'; }
summary_shape() { jq -S 'del(.run_id, .ts) | .steps |= map(del(.duration_ms) | .log |= sub("runs/[^/]+"; "runs/X"))' "$1"; }

world_new
world_use_fixture satisfied

# ── side by side reads as serial ─────────────────────────────────────────────
bump_now_secs 60
ARI_DOTFILES_SERIAL=1 ARI_DOTFILES_NO_CACHE=1 nm check
SERIAL_RC="${RC}" SERIAL_OUT="$(mask <<< "${OUT}")" SERIAL_ERR="$(mask <<< "${ERR}")"
RUN="$(newest_run_dir)"
SERIAL_LOG="$(mask < "${RUN}/run.log")" SERIAL_SUMMARY="$(summary_shape "${RUN}/summary.json")"
bump_now_secs 60
ARI_DOTFILES_NO_CACHE=1 nm check
RUN="$(newest_run_dir)"
assert_eq "same exit code" "${SERIAL_RC}" "${RC}"
assert_eq "same stdout" "${SERIAL_OUT}" "$(mask <<< "${OUT}")"
assert_eq "same stderr, line for line" "${SERIAL_ERR}" "$(mask <<< "${ERR}")"
assert_eq "same run.log, line for line" "${SERIAL_LOG}" "$(mask < "${RUN}/run.log")"
assert_eq "same summary.json but for durations" "${SERIAL_SUMMARY}" "$(summary_shape "${RUN}/summary.json")"
assert_eq "no buffer left in the run dir" "" "$(/bin/ls -A "${RUN}" | grep '^\.' || true)"

# ── claude_skills: a hit, then a miss when a link goes ───────────────────────
TIER="${HOME}/.config/claude/skills"
FARM="${HOME}/.claude/skills"
mkdir -p "${TIER}/foo"
cp -R "${ORIG_CONFIG_DIR}/claude/skills/ari-dotfiles-skill-registry" "${TIER}/"
cp -R "${ORIG_CONFIG_DIR}/claude/skills/ari-skill-shellscripts" "${TIER}/"
printf -- '---\nname: foo\n---\n' > "${TIER}/foo/SKILL.md"
bump_now_secs 60
nm apply claude_skills
assert_eq "apply links the skills" 0 "${RC}"
age() { find "${HOME}/.claude" "${HOME}/.config/claude" "${HOME}/.local" "${HOME}/.gitmodules" -exec touch -h -t 202001010000 {} + 2>/dev/null || true; }
age
check_skills() { bump_now_secs 60; nm check --only claude_skills --json; out_json > /dev/null; }
check_skills
assert_eq "linked → ok" ok "$(step_get claude_skills .status)"
assert_not_contains "first run is live" "$(step_get claude_skills .detail)" "cached: true"
check_skills
assert_eq "hit keeps the status" ok "$(step_get claude_skills .status)"
assert_contains "hit is marked" "$(step_get claude_skills .detail)" "cached: true"
rm -f "${FARM}/foo"
age
check_skills
assert_eq "a removed link misses → fail" fail "$(step_get claude_skills .status)"
assert_eq "reason links_missing" links_missing "$(step_get claude_skills .reason)"
ln -s "${TIER}/foo" "${FARM}/foo"; age
check_skills
assert_eq "relinked → ok" ok "$(step_get claude_skills .status)"
rm -rf "${TIER}/foo"
age
check_skills
assert_eq "a dangling link misses → fail" fail "$(step_get claude_skills .status)"
assert_contains "names the dangling link" "$(step_get claude_skills .detail)" "dangling='foo'"

# ── seams are never cached ───────────────────────────────────────────────────
bump_now_secs 60
nm check --only bob_neovim --json
assert_no_file "bob shim → no cache entry" "${ARI_DOTFILES_STATE_DIR}/cache/bob_neovim.fp"
mkdir -p "${FIX}/Raycast.app"
printf '{"bindings":[]}\n' > "${FIX}/bindings.json"
ARI_DOTFILES_RAYCAST_APP="${FIX}/Raycast.app" ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${FIX}/bindings.json" nm check --only raycast_sync --json
assert_no_file "bindings command → no raycast cache entry" "${ARI_DOTFILES_STATE_DIR}/cache/raycast_sync.fp"

report
