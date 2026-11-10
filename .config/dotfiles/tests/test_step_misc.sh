#!/usr/bin/env bash
# The small steps: neovim, claude, terminal_nerdfont, terminal_config, home_strays, nix_port,
# karabiner, claude_notifications, dotfiles_jobs — each check's verdicts and the dry-run of each apply.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied

check_step() { bump_now_secs 60; nm check --only "$1" --json; out_json > /dev/null; }
dry_step() { bump_now_secs 60; nm init --only "$1" --dry-run; }
status_of() { step_get "$1" .status; }
reason_of() { step_get "$1" .reason; }

# ── neovim ────────────────────────────────────────────────────────────────
# The shim stands in for the flake's build: the world's "store" is its shim dir.
export ARI_DOTFILES_NIX_STORE="${FIX}/shims"
check_step neovim
assert_eq "nix nvim, clean headless start → ok" ok "$(status_of neovim)"
assert_contains "detail names the version" "$(step_get neovim .detail)" "v0.13.0-dev"
assert_contains "the start was headless" "$(shim_log nvim)" "--headless"
export NVIM_SHIM_STDERR="Error detected while processing init.lua: E5113: module 'oops' not found"
check_step neovim
assert_eq "start prints an error → fail" fail "$(status_of neovim)"
assert_eq "reason nvim_start_errors" nvim_start_errors "$(reason_of neovim)"
assert_eq "nvim_start_errors is manual" true "$(step_get neovim .manual)"
assert_contains "detail quotes the error" "$(step_get neovim .detail)" "E5113"
assert_contains "the error is logged" "$(cat "${HOME}/.local/state/nvim/headless-start.log")" "E5113"
unset NVIM_SHIM_STDERR
export NVIM_SHIM_RC=1
check_step neovim
assert_eq "start exits non-zero → fail" fail "$(status_of neovim)"
unset NVIM_SHIM_RC
export ARI_DOTFILES_NIX_STORE="/nix/store"
check_step neovim
assert_eq "nvim outside the store → fail" fail "$(status_of neovim)"
assert_eq "reason nvim_not_nix" nvim_not_nix "$(reason_of neovim)"
shim_remove nvim
check_step neovim
assert_eq "no nvim → fail" fail "$(status_of neovim)"
assert_eq "reason nvim_missing" nvim_missing "$(reason_of neovim)"
shim_add nvim
export ARI_DOTFILES_NIX_STORE="${FIX}/shims"

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
# launchd's PATH lacks ~/.local/bin, where the installer puts claude; the checker must still see it.
mkdir -p "${HOME}/.local/bin"
cp "${TESTS_DIR}/shims/claude" "${HOME}/.local/bin/claude"
chmod +x "${HOME}/.local/bin/claude"
check_step claude
assert_eq "claude only in ~/.local/bin → ok" ok "$(status_of claude)"
assert_contains "detail names the ~/.local/bin path" "$(step_get claude .detail)" "${HOME}/.local/bin/claude"
rm -f "${HOME}/.local/bin/claude"
shim_add claude

# ── terminal_nerdfont ─────────────────────────────────────────────────────────
# Terminal.app keeps each profile's font as a base64 NSKeyedArchiver NSFont blob; build one.
terminal_plist_with_font() {
  local name="$1" dir="${HOME}/Library/Preferences"
  mkdir -p "${dir}"
  cat > "${FIX}/font.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>\$archiver</key><string>NSKeyedArchiver</string>
  <key>\$objects</key><array>
    <string>\$null</string>
    <dict><key>\$class</key><dict><key>CF\$UID</key><integer>3</integer></dict>
          <key>NSName</key><dict><key>CF\$UID</key><integer>2</integer></dict>
          <key>NSSize</key><real>18</real><key>NSfFlags</key><integer>16</integer></dict>
    <string>${name}</string>
    <dict><key>\$classes</key><array><string>NSFont</string><string>NSObject</string></array>
          <key>\$classname</key><string>NSFont</string></dict>
  </array>
  <key>\$top</key><dict><key>root</key><dict><key>CF\$UID</key><integer>1</integer></dict></dict>
  <key>\$version</key><integer>100000</integer>
</dict></plist>
EOF
  local b64
  b64="$(plutil -convert binary1 -o - "${FIX}/font.xml" | base64)"
  cat > "${dir}/com.apple.Terminal.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Default Window Settings</key><string>Pro</string>
  <key>Window Settings</key><dict>
    <key>Basic</key><dict><key>name</key><string>Basic</string></dict>
    <key>Pro</key><dict><key>Font</key><data>${b64}</data><key>name</key><string>Pro</string></dict>
  </dict>
</dict></plist>
EOF
  plutil -lint -s "${dir}/com.apple.Terminal.plist"
}

# The font is a file in a font dir, however it got there: nix-darwin's Nix Fonts subdir here.
export ARI_DOTFILES_FONT_DIRS="${FIX}/fonts/user:${FIX}/fonts/system"
mkdir -p "${FIX}/fonts/user" "${FIX}/fonts/system/Nix Fonts"
: > "${FIX}/fonts/system/Nix Fonts/CaskaydiaMonoNerdFontMono-Regular.ttf"
check_step terminal_nerdfont
assert_eq "no Terminal prefs → warn" warn "$(status_of terminal_nerdfont)"
assert_eq "reason manual_font" manual_font "$(reason_of terminal_nerdfont)"
assert_eq "manual_font is manual" true "$(step_get terminal_nerdfont .manual)"
terminal_plist_with_font "Menlo-Regular"
check_step terminal_nerdfont
assert_eq "no profile uses a Nerd Font → fail" fail "$(status_of terminal_nerdfont)"
assert_eq "reason font_not_set" font_not_set "$(reason_of terminal_nerdfont)"
assert_eq "font_not_set is manual" true "$(step_get terminal_nerdfont .manual)"
terminal_plist_with_font "CaskaydiaMonoNFM-Regular"
check_step terminal_nerdfont
assert_eq "one profile uses a Nerd Font → ok" ok "$(status_of terminal_nerdfont)"
assert_eq "reason font_set" font_set "$(reason_of terminal_nerdfont)"
assert_contains "detail names the font" "$(step_get terminal_nerdfont .detail)" "CaskaydiaMonoNFM-Regular"
rm "${FIX}/fonts/system/Nix Fonts/CaskaydiaMonoNerdFontMono-Regular.ttf"
check_step terminal_nerdfont
assert_eq "nerd font absent → fail" fail "$(status_of terminal_nerdfont)"
assert_eq "reason font_missing" font_missing "$(reason_of terminal_nerdfont)"
assert_contains "fix points at the switch" "$(step_get terminal_nerdfont .fix)" "darwin-rebuild switch"
# A font restored from a backup into ~/Library/Fonts counts: no package needed.
: > "${FIX}/fonts/user/CaskaydiaMonoNerdFont-Bold.ttf"
check_step terminal_nerdfont
assert_eq "a restored font file → ok" ok "$(status_of terminal_nerdfont)"
export ARI_DOTFILES_FONT_DIRS="${FIX}/fonts"   # back to the world's font dir

# ── terminal_config ───────────────────────────────────────────────────────────
rm -f "${HOME}/Library/Preferences/com.apple.Terminal.plist"
check_step terminal_config
assert_eq "no Terminal prefs → skip" skip "$(status_of terminal_config)"
assert_eq "reason no_profiles" no_profiles "$(reason_of terminal_config)"
terminal_plist_with_font "Menlo-Regular"
plutil -insert 'Window Settings.Basic.useOptionAsMetaKey' -bool true "${HOME}/Library/Preferences/com.apple.Terminal.plist"
TP="${HOME}/Library/Preferences/com.apple.Terminal.plist"
check_step terminal_config
assert_eq "the active profile without Option as Meta → fail" fail "$(status_of terminal_config)"
assert_eq "reason active_not_meta" active_not_meta "$(reason_of terminal_config)"
assert_contains "detail names the active profile" "$(step_get terminal_config .detail)" "Meta: Pro |"
assert_not_contains "detail leaves out the one already set" "$(step_get terminal_config .detail)" "Basic"
assert_eq "init fixes it" false "$(step_get terminal_config .manual)"
plutil -replace 'Default Window Settings' -string Basic "${TP}"
check_step terminal_config
assert_eq "an inactive profile without Option as Meta → fail" fail "$(status_of terminal_config)"
assert_eq "reason option_not_meta" option_not_meta "$(reason_of terminal_config)"
plutil -replace 'Startup Window Settings' -string Homebrew "${TP}"
check_step terminal_config
assert_eq "an active built-in never saved → fail" fail "$(status_of terminal_config)"
assert_eq "reason active_unsaved" active_unsaved "$(reason_of terminal_config)"
assert_eq "active_unsaved is manual" true "$(step_get terminal_config .manual)"
assert_contains "the fix is the checkbox" "$(step_get terminal_config .fix)" "Profiles -> Homebrew -> Keyboard"
plutil -remove 'Startup Window Settings' "${TP}"
plutil -replace 'Default Window Settings' -string Pro "${TP}"
dry_step terminal_config
assert_contains "dry-run logs the apply plan" "${ERR}" "would run apply::terminal_config"
assert_not_contains "dry-run writes nothing" "$(shim_log defaults)" "import"
bump_now_secs 60; nm apply terminal_config
assert_contains "apply imports through defaults" "$(shim_log defaults)" "import ${HOME}/Library/Preferences/com.apple.Terminal "
check_step terminal_config
assert_eq "after apply → ok" ok "$(status_of terminal_config)"
assert_eq "reason option_is_meta" option_is_meta "$(reason_of terminal_config)"
assert_contains "detail names the active profile" "$(step_get terminal_config .detail)" "active: Pro |"
rm -f "${HOME}/Library/Preferences/com.apple.Terminal.plist"

# ── home_strays ───────────────────────────────────────────────────────────────
check_step home_strays
assert_eq "no stray shell files → ok" ok "$(status_of home_strays)"
printf '. "$HOME/.cargo/env"\n' > "${HOME}/.profile"
: > "${HOME}/.bash_aliases"
check_step home_strays
assert_eq "stray shell files → fail" fail "$(status_of home_strays)"
assert_eq "reason stray_files" stray_files "$(reason_of home_strays)"
assert_eq "stray_files is manual" true "$(step_get home_strays .manual)"
assert_contains "detail names both" "$(step_get home_strays .detail)" "~/.profile, ~/.bash_aliases"
assert_contains "the fix removes them after porting" "$(step_get home_strays .fix)" "then: rm ~/.profile ~/.bash_aliases"
dry_step home_strays
assert_file "a dry run leaves them" "${HOME}/.profile"
rm -f "${HOME}/.profile" "${HOME}/.bash_aliases"

# ── nix_port ──────────────────────────────────────────────────────────────────
check_step nix_port
assert_eq "the world has finished the port → ok" ok "$(status_of nix_port)"
rm -rf "${ARI_DOTFILES_NIX_CLONE}/.git" "${ARI_DOTFILES_NIX_SYSTEM}"
mkdir -p "${XDG_DATA_HOME}/tmuxinator" "${XDG_DATA_HOME}/raycast-snippets"
: > "${XDG_DATA_HOME}/tmuxinator/work.yml"; printf '[]\n' > "${XDG_DATA_HOME}/raycast-snippets/snippets.json"
check_step nix_port
assert_eq "items open → fail" fail "$(status_of nix_port)"
assert_eq "reason transition_open" transition_open "$(reason_of nix_port)"
assert_eq "transition_open is the apply's, not manual" false "$(step_get nix_port .manual)"
D="$(step_get nix_port .detail)"
assert_contains "counts the open items" "${D}" "4 transition item(s) open, in order:"
assert_contains "1: the clone" "${D}" "1. the shared tier is not the ~/dotfiles clone"
assert_contains "4: the first switch, after the local data moved into the flake" "${D}" "4. nix-darwin has never switched here"
assert_contains "a tmuxinator project left behind, with its option" "${D}" "programs.tmuxinatorProjects.work = ./tmuxinator/work.yml;"
assert_contains "the old snippets file, with its option" "${D}" "programs.raycastSnippets.localFile = ./raycast-snippets.json;"
assert_contains "the fix is the apply" "$(step_get nix_port .fix)" "apply nix_port"
mv "${ARI_DOTFILES_NIX_FLAKE}/flake.nix" "${FIX}/flake.nix.bak"
check_step nix_port
assert_contains "no local flake is an item" "$(step_get nix_port .detail)" "no local flake | path='${ARI_DOTFILES_NIX_FLAKE}/flake.nix'"
mv "${FIX}/flake.nix.bak" "${ARI_DOTFILES_NIX_FLAKE}/flake.nix"
mkdir -p "${ARI_DOTFILES_NIX_CLONE}/.git" "${ARI_DOTFILES_NIX_SYSTEM}"
rm -rf "${XDG_DATA_HOME}/tmuxinator" "${XDG_DATA_HOME}/raycast-snippets"
check_step nix_port
assert_eq "all done again → ok" ok "$(status_of nix_port)"

# ── karabiner ─────────────────────────────────────────────────────────────────
# karabiner.nix places karabiner.json and parses it at the switch; the step runs only the
# healthcheck.
check_step karabiner
assert_eq "no healthcheck → skip" skip "$(status_of karabiner)"
assert_eq "reason no_healthcheck" no_healthcheck "$(reason_of karabiner)"
seed_fake_healthcheck 1
check_step karabiner
assert_eq "healthcheck exit 1 → warn" warn "$(status_of karabiner)"
assert_eq "reason karabiner_healthcheck" karabiner_healthcheck "$(reason_of karabiner)"
assert_contains "detail carries issues=2" "$(step_get karabiner .detail)" "issues=2"
seed_fake_healthcheck 0
check_step karabiner
assert_eq "healthcheck exit 0 → ok" ok "$(status_of karabiner)"
# A fresh machine has the healthcheck (df) before its logging lib (~/.claude/skills): not run.
rm -f "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
check_step karabiner
assert_eq "healthcheck without its logging lib → skip" skip "$(status_of karabiner)"
assert_eq "reason no_logging_lib" no_logging_lib "$(reason_of karabiner)"

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
jq -n --arg cmd "${HOME}/.config/claude/bin/notification-fire.sh" '{hooks: {Notification: [{hooks: [{type: "command", command: $cmd}]}]}}' > "${HOME}/.claude/settings.json"
check_step claude_notifications
assert_eq "notification wired but no PreToolUse guard → fail" fail "$(status_of claude_notifications)"
assert_eq "reason guard_mismatch" guard_mismatch "$(reason_of claude_notifications)"
jq --arg cmd "${HOME}/.config/claude/bin/pretooluse-headless-chrome-guard.sh" '.hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}]' "${HOME}/.claude/settings.json" > "${HOME}/.claude/settings.json.tmp" && mv "${HOME}/.claude/settings.json.tmp" "${HOME}/.claude/settings.json"
check_step claude_notifications
assert_eq "notification and guard wired but no Stop hook → fail" fail "$(status_of claude_notifications)"
assert_eq "reason stop_mismatch" stop_mismatch "$(reason_of claude_notifications)"
"${HOME}/.config/claude/bin/initialize.sh"
check_step claude_notifications
assert_eq "all three hooks wired → ok" ok "$(status_of claude_notifications)"
assert_json "guard hook wired" "${HOME}/.claude/settings.json" '[.hooks.PreToolUse[].hooks[].command] | map(select(endswith("pretooluse-headless-chrome-guard.sh"))) | length' "1"
assert_json "stop hook wired" "${HOME}/.claude/settings.json" '.hooks.Stop[0].hooks[0].command' "${HOME}/.config/claude/bin/stop-fire.sh"
# macOS's per-app switch: usernoted keeps it as bit 25 of the app's flags.
_nc="${HOME}/usernoted.plist"
export ARI_DOTFILES_USERNOTED_PLIST="${_nc}"
hermetic_env
_nc_write() { python3 -I -c 'import plistlib,sys; plistlib.dump({"apps": [{"bundle-id": sys.argv[2], "flags": int(sys.argv[3])}]}, open(sys.argv[1], "wb"))' "${_nc}" "$@"; }
_nc_write fr.julienxx.oss.terminal-notifier $(( 1 << 25 | 12 ))
check_step claude_notifications
assert_eq "terminal-notifier allowed in macOS → ok" ok "$(status_of claude_notifications)"
_nc_write fr.julienxx.oss.terminal-notifier 12
check_step claude_notifications
assert_eq "terminal-notifier switched off in macOS → fail" fail "$(status_of claude_notifications)"
assert_eq "reason notifications_off" notifications_off "$(reason_of claude_notifications)"
_nc_write com.example.other $(( 1 << 25 ))
check_step claude_notifications
assert_eq "terminal-notifier never registered → warn" warn "$(status_of claude_notifications)"
unset ARI_DOTFILES_USERNOTED_PLIST
hermetic_env

# ── dotfiles_jobs ────────────────────────────────────────────────────────────────
JOBS_LABEL="com.$(id -un).dotfiles-jobs"
JOBS_PLIST="${HOME}/Library/LaunchAgents/${JOBS_LABEL}.plist"
check_step dotfiles_jobs
assert_eq "plist missing → fail" fail "$(status_of dotfiles_jobs)"
assert_eq "reason not_installed" not_installed "$(reason_of dotfiles_jobs)"
jq -n --arg label "${JOBS_LABEL}" '{Label: $label, ProgramArguments: ["/bin/zsh", "dotfiles", "jobs", "tick"], StartInterval: 300}' \
  | plutil -convert xml1 - -o "${JOBS_PLIST}"
touch "${LAUNCHCTL_SHIM_STATE}/${JOBS_LABEL}"
check_step dotfiles_jobs
assert_eq "plist present, lints, loaded → ok" ok "$(status_of dotfiles_jobs)"
rm -f "${LAUNCHCTL_SHIM_STATE}/${JOBS_LABEL}"
check_step dotfiles_jobs
assert_eq "plist present but unloaded → fail" fail "$(status_of dotfiles_jobs)"
assert_eq "reason not_loaded" not_loaded "$(reason_of dotfiles_jobs)"
assert_no_mutation "misc checks and dry-runs are read-only"

# A plist whose agent is in the Nix store is nix-darwin's: the apply leaves it and the job alone.
jq -n --arg label "${JOBS_LABEL}" --arg agent "${ARI_DOTFILES_NIX_STORE}/abc-dotfiles-jobs-agent-1/bin/dotfiles-jobs-agent" \
  '{Label: $label, ProgramArguments: [$agent, "dotfiles", "300", "com.apple.screenIsUnlocked"], KeepAlive: true}' \
  | plutil -convert xml1 - -o "${JOBS_PLIST}"
cp "${JOBS_PLIST}" "${FIX}/nix-plist"
: > "${BREW_SHIM_LOG_DIR}/launchctl.log"
bump_now_secs 60
nm init --only dotfiles_jobs
assert_contains "nix-managed: the apply defers" "$(cat "$(newest_run_dir)/dotfiles_jobs.log")" "managed by nix-darwin"
assert_eq "nix-managed: the plist is untouched" "" "$(cmp "${JOBS_PLIST}" "${FIX}/nix-plist" 2>&1)"
assert_eq "nix-managed: no bootstrap" "" "$(grep bootstrap "${BREW_SHIM_LOG_DIR}/launchctl.log")"
assert_no_file "nix-managed: nothing compiled" "${XDG_STATE_HOME}/dotfiles/jobs/bin/dotfiles-jobs-agent"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
