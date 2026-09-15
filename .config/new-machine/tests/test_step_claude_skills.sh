#!/usr/bin/env bash
# claude_skills: skip without the registry, fail on missing/dangling links, apply links and
# prunes through the registry skill, warn on a real dir shadowing a tier copy.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
TIER="${HOME}/.config/claude/skills"
FARM="${HOME}/.claude/skills"

check_skills() { bump_now_secs 60; nm check --only claude_skills --json; out_json > /dev/null; }

check_skills
assert_eq "no registry → skip" skip "$(step_get claude_skills .status)"
assert_eq "reason no_registry" no_registry "$(step_get claude_skills .reason)"

# The shared tier as a checkout would leave it: the registry skill, the logging lib it
# sources, and one more skill to link.
mkdir -p "${TIER}"
cp -R "${ORIG_CONFIG_DIR}/claude/skills/ari-dotfiles-skill-registry" "${TIER}/"
cp -R "${ORIG_CONFIG_DIR}/claude/skills/ari-skill-shellscripts" "${TIER}/"
mkdir -p "${TIER}/foo"
printf -- '---\nname: foo\n---\n' > "${TIER}/foo/SKILL.md"

check_skills
assert_eq "tier held, farm empty → fail" fail "$(step_get claude_skills .status)"
assert_eq "reason links_missing" links_missing "$(step_get claude_skills .reason)"
assert_contains "detail names foo" "$(step_get claude_skills .detail)" "foo"
assert_contains "detail names the registry itself" "$(step_get claude_skills .detail)" "ari-dotfiles-skill-registry"
assert_eq "fix is apply" "new-machine apply claude_skills" "$(step_get claude_skills .fix)"

bump_now_secs 60
nm apply claude_skills
assert_eq "apply exits 0" 0 "${RC}"
assert_eq "foo is a symlink into the tier" "${TIER}/foo" "$(readlink "${FARM}/foo")"
assert_eq "registry is a symlink into the tier" "${TIER}/ari-dotfiles-skill-registry" "$(readlink "${FARM}/ari-dotfiles-skill-registry")"

check_skills
assert_eq "linked → ok" ok "$(step_get claude_skills .status)"
assert_contains "detail counts 3" "$(step_get claude_skills .detail)" "3 skills linked"

rm -rf "${TIER}/foo"
check_skills
assert_eq "tier dir removed → fail" fail "$(step_get claude_skills .status)"
assert_contains "detail says dangling foo" "$(step_get claude_skills .detail)" "dangling='foo'"

bump_now_secs 60
nm apply claude_skills
assert_eq "apply (prune) exits 0" 0 "${RC}"
assert_no_file "dangling link pruned" "${FARM}/foo"

check_skills
assert_eq "after prune → ok" ok "$(step_get claude_skills .status)"
assert_contains "detail counts 2" "$(step_get claude_skills .detail)" "2 skills linked"

mkdir -p "${TIER}/bar" "${FARM}/bar"
check_skills
assert_eq "real dir shadows tier copy → warn" warn "$(step_get claude_skills .status)"
assert_eq "reason needs_hand" needs_hand "$(step_get claude_skills .reason)"
assert_contains "detail names bar:shadowed" "$(step_get claude_skills .detail)" "bar:shadowed"
assert_eq "needs_hand is manual" true "$(step_get claude_skills .manual)"

bump_now_secs 60
nm apply claude_skills
assert_eq "apply leaves the shadowed dir alone" 0 "${RC}"
assert_eq "bar stays a real dir" "" "$(readlink "${FARM}/bar" || true)"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, fix}' "${FIX}/out.json" >&2; fi
report
