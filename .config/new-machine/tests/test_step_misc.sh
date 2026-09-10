#!/usr/bin/env bash
# The small steps: bob_neovim, claude, terminal_nerdfont, karabiner, claude_notifications,
# git_health — each check's verdicts and the dry-run of each apply.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

check_step() { bump_now_secs 60; nm check --only "$1" --json; out_json > /dev/null; }
dry_step() { bump_now_secs 60; nm setup --only "$1" --dry-run; }
status_of() { step_get "$1" .status; }
reason_of() { step_get "$1" .reason; }

# ── bob_neovim ────────────────────────────────────────────────────────────────
export BOB_SHIM_LS="Installed: v0.11.2 Used"
check_step bob_neovim
assert_eq "bob Used → ok" ok "$(status_of bob_neovim)"
export BOB_SHIM_LS="v0.11.2"
check_step bob_neovim
assert_eq "bob not used → fail" fail "$(status_of bob_neovim)"
assert_eq "reason nvim_missing" nvim_missing "$(reason_of bob_neovim)"
dry_step bob_neovim
assert_contains "dry-run logs the bob apply plan" "${ERR}" "would run apply::bob_neovim"
assert_contains "dry-run plan names bob install" "$(cat "$(newest_run_dir)/bob_neovim.log")" "cmd='bob install latest'"
assert_not_contains "dry-run installs nothing" "$(shim_log bob)" "install"
shim_remove bob
check_step bob_neovim
assert_eq "no bob → fail" fail "$(status_of bob_neovim)"
assert_eq "reason bob_missing" bob_missing "$(reason_of bob_neovim)"
assert_eq "bob_missing is manual" true "$(step_get bob_neovim .manual)"
assert_contains "fix points at brew_pkgs" "$(step_get bob_neovim .fix)" "new-machine apply brew_pkgs"
shim_add bob

# ── claude ────────────────────────────────────────────────────────────────────
check_step claude
assert_eq "claude present → ok" ok "$(status_of claude)"
assert_contains "detail carries the version" "$(step_get claude .detail)" "2.1.267"
shim_remove claude
check_step claude
assert_eq "claude absent → fail" fail "$(status_of claude)"
assert_eq "reason claude_missing" claude_missing "$(reason_of claude)"
dry_step claude
assert_contains "dry-run logs the claude apply plan" "${ERR}" "would run apply::claude"
claude_plan="$(cat "$(newest_run_dir)/claude.log")"
assert_contains "dry-run plan pipes the installer to sh" "${claude_plan}" "cmd='zsh -c curl -fsSL"
assert_contains "dry-run plan names the installer URL" "${claude_plan}" "https://claude.ai/install.sh"
assert_eq "curl never called" "" "$(shim_log curl)"
shim_add claude

# ── terminal_nerdfont ─────────────────────────────────────────────────────────
check_step brew,terminal_nerdfont
assert_eq "nerd font present → warn" warn "$(status_of terminal_nerdfont)"
assert_eq "reason manual_font" manual_font "$(reason_of terminal_nerdfont)"
assert_eq "manual_font is manual" true "$(step_get terminal_nerdfont .manual)"
world_use_fixture drift
check_step brew,terminal_nerdfont
assert_eq "nerd font absent → fail" fail "$(status_of terminal_nerdfont)"
assert_eq "reason font_missing" font_missing "$(reason_of terminal_nerdfont)"
assert_contains "fix points at brew_pkgs" "$(step_get terminal_nerdfont .fix)" "new-machine apply brew_pkgs"
world_use_fixture satisfied

# ── karabiner ─────────────────────────────────────────────────────────────────
KJ="${HOME}/.config/karabiner/karabiner.json"
mkdir -p "${HOME}/.config/karabiner"
shim_add npm
check_step karabiner
assert_eq "karabiner.json missing → fail" fail "$(status_of karabiner)"
assert_eq "reason karabiner_config (missing)" karabiner_config "$(reason_of karabiner)"
printf '{"z": 1, "a": 2}\n' > "${KJ}"
check_step karabiner
assert_eq "unsorted karabiner.json → fail" fail "$(status_of karabiner)"
assert_eq "reason karabiner_config (unsorted)" karabiner_config "$(reason_of karabiner)"
shim_remove npm
check_step karabiner
assert_eq "no npm + bake needed → skip" skip "$(status_of karabiner)"
assert_eq "reason no_npm" no_npm "$(reason_of karabiner)"
jq -S -n '{a: 2, z: 1}' > "${KJ}"
check_step karabiner
assert_eq "sorted karabiner.json → ok" ok "$(status_of karabiner)"
seed_fake_healthcheck 1
check_step karabiner
assert_eq "healthcheck exit 1 → warn" warn "$(status_of karabiner)"
assert_eq "reason karabiner_healthcheck" karabiner_healthcheck "$(reason_of karabiner)"
assert_contains "detail carries issues=2" "$(step_get karabiner .detail)" "issues=2"
seed_fake_healthcheck 0
check_step karabiner
assert_eq "healthcheck exit 0 → ok" ok "$(status_of karabiner)"
# A fresh machine has the healthcheck (df) before its logging lib (~/.claude/skills): not run, not a warn.
rm -f "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
check_step karabiner
assert_eq "healthcheck without its logging lib → ok" ok "$(status_of karabiner)"
assert_contains "detail says the healthcheck was unusable" "$(step_get karabiner .detail)" "logging lib missing"

# ── claude_notifications ──────────────────────────────────────────────────────
check_step claude_notifications
assert_eq "no initialize.sh → skip" skip "$(status_of claude_notifications)"
assert_eq "reason no_initialize" no_initialize "$(reason_of claude_notifications)"
mkdir -p "${HOME}/.config/claude/bin" "${HOME}/.claude"
cp "${TESTS_DIR}/fixtures/df-remote/.config/claude/bin/initialize.sh" "${HOME}/.config/claude/bin/initialize.sh"
chmod +x "${HOME}/.config/claude/bin/initialize.sh"
jq -n '{hooks: {Notification: [{hooks: [{type: "command", command: "/somewhere/else.sh"}]}]}}' > "${HOME}/.claude/settings.json"
check_step claude_notifications
assert_eq "hook mismatch → fail" fail "$(status_of claude_notifications)"
assert_eq "reason hook_mismatch" hook_mismatch "$(reason_of claude_notifications)"
dry_step claude_notifications
assert_contains "dry-run logs the notifications apply plan" "${ERR}" "would run apply::claude_notifications"
assert_json "settings.json untouched by the dry-run" "${HOME}/.claude/settings.json" '.hooks.Notification[0].hooks[0].command' "/somewhere/else.sh"
"${HOME}/.config/claude/bin/initialize.sh"
check_step claude_notifications
assert_eq "hook wired → ok" ok "$(status_of claude_notifications)"

# ── git_health ────────────────────────────────────────────────────────────────
GH_LABEL="com.$(id -un).git-health"
GH_PLIST="${HOME}/Library/LaunchAgents/${GH_LABEL}.plist"
check_step git_health
assert_eq "plist missing → fail" fail "$(status_of git_health)"
assert_eq "reason not_installed" not_installed "$(reason_of git_health)"
jq -n --arg label "${GH_LABEL}" '{Label: $label, ProgramArguments: ["/bin/zsh", "git-health", "--all"], StartCalendarInterval: {Minute: 20}}' \
  | plutil -convert xml1 - -o "${GH_PLIST}"
touch "${LAUNCHCTL_SHIM_STATE}/${GH_LABEL}"
check_step git_health
assert_eq "plist present, lints, loaded → ok" ok "$(status_of git_health)"
rm -f "${LAUNCHCTL_SHIM_STATE}/${GH_LABEL}"
check_step git_health
assert_eq "plist present but unloaded → fail" fail "$(status_of git_health)"
assert_eq "reason not_loaded" not_loaded "$(reason_of git_health)"
assert_no_mutation "misc checks and dry-runs are read-only"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
