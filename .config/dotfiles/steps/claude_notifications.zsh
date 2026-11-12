# step claude_notifications — the Claude Code hooks initialize.sh wires: Notification →
# notification-fire.sh, Stop → stop-fire.sh (a banner at the end of every turn) and the
# PreToolUse headless-Chrome guard; terminal-notifier resolves.
step::declare claude_notifications --group tools \
  --desc "Claude Code hooks wired: Notification → notification-fire.sh, Stop → stop-fire.sh, PreToolUse guard → pretooluse-headless-chrome-guard.sh; terminal-notifier resolves and macOS allows its notifications" \
  --apply "runs ~/.config/claude/bin/initialize.sh: installs terminal-notifier and writes the three hooks into ~/.claude/settings.json"
step::watches claude_notifications '.config/claude/bin/**'

readonly CLAUDE_NOTIFIER_BUNDLE='fr.julienxx.oss.terminal-notifier'

# Prints "on <style>", off, unregistered (no entry for the bundle) or unknown (no usernoted prefs
# file, as in the test world, or an unreadable one). The style is the app's alert style in System
# Settings > Notifications: persistent (flags bit 4: the banner stays until dismissed), temporary
# (bit 3: it leaves after a few seconds) or none.
step::claude_notifications::allowed() {
  local plist="${ARI_DOTFILES_USERNOTED_PLIST:-${HOME}/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist}"
  [[ -r "${plist}" ]] || { print -r -- unknown; return 0; }
  python3 -I - "${plist}" "${CLAUDE_NOTIFIER_BUNDLE}" 2>/dev/null <<'PY' || print -r -- unknown
import plistlib, sys
apps = plistlib.load(open(sys.argv[1], "rb")).get("apps", [])
hit = [a for a in apps if a.get("bundle-id") == sys.argv[2]]
flags = hit[0].get("flags", 0) if hit else 0
style = "persistent" if flags >> 4 & 1 else "temporary" if flags >> 3 & 1 else "none"
print("unregistered" if not hit else (f"on {style}" if flags >> 25 & 1 else "off"))
PY
}

check::claude_notifications() {
  local init="${HOME}/.config/claude/bin/initialize.sh" expected="${HOME}/.config/claude/bin/notification-fire.sh"
  local settings="${HOME}/.claude/settings.json"
  if [[ ! -x "${init}" ]]; then
    verdict skip no_initialize -d "init script missing | path='${init}'"
    return 0
  fi
  local current=""
  if [[ -f "${settings}" ]]; then
    current="$(jq -r '.hooks.Notification[0].hooks[0].command // ""' "${settings}" 2>/dev/null || true)"
  fi
  if [[ "${current}" != "${expected}" ]]; then
    verdict fail hook_mismatch -d "hook='${current}' expected='${expected}' settings='${settings}'" -f "${CLI_NAME} apply claude_notifications"
    return 0
  fi
  # The headless-Chrome guard is a second hook initialize.sh wires (PreToolUse, matcher Bash).
  local guard="${HOME}/.config/claude/bin/pretooluse-headless-chrome-guard.sh" guard_hooks
  guard_hooks="$(jq -r --arg cmd "${guard}" '[.hooks.PreToolUse // [] | .[].hooks[]? | select(.command == $cmd)] | length' "${settings}" 2>/dev/null || echo 0)"
  if [[ "${guard_hooks}" != 1 ]]; then
    verdict fail guard_mismatch -d "PreToolUse guard hooks=${guard_hooks} expected=1 | guard='${guard}' settings='${settings}'" -f "${CLI_NAME} apply claude_notifications"
    return 0
  fi
  local stop="${HOME}/.config/claude/bin/stop-fire.sh" stop_hooks
  stop_hooks="$(jq -r --arg cmd "${stop}" '[.hooks.Stop // [] | .[].hooks[]? | select(.command == $cmd)] | length' "${settings}" 2>/dev/null || echo 0)"
  if [[ "${stop_hooks}" != 1 ]]; then
    verdict fail stop_mismatch -d "Stop hooks=${stop_hooks} expected=1 | stop='${stop}' settings='${settings}'" -f "${CLI_NAME} apply claude_notifications"
    return 0
  fi
  if [[ -z "${ARI_DOTFILES_NOTIFIER}" ]] || ! command -v "${ARI_DOTFILES_NOTIFIER}" >/dev/null 2>&1; then
    verdict fail notifier_missing -d "atn (the terminal-notifier shim, ~/.config/bin) not found" -f "${CLI_NAME} apply claude_notifications"
    return 0
  fi
  # macOS can switch terminal-notifier off (System Settings > Notifications); then every banner is
  # dropped silently. usernoted keeps the switch as bit 25 of the app's flags; the file is read
  # only (macOS does not support writing it), so this is a manual fix.
  local allowed
  allowed="$(step::claude_notifications::allowed)"
  case "${allowed}" in
    off)
      verdict fail notifications_off -d "terminal-notifier's notifications are switched off in macOS | bundle='${CLAUDE_NOTIFIER_BUNDLE}'" -f "System Settings > Notifications > terminal-notifier > Allow Notifications" -m
      return 0 ;;
    unregistered)
      verdict warn notifier_unregistered -d "macOS has no notification setting for terminal-notifier yet; it appears after the first banner | bundle='${CLAUDE_NOTIFIER_BUNDLE}'" -f "~/.config/claude/bin/notification-fire.sh test, then allow it when macOS asks" -m
      return 0 ;;
  esac
  # The alert style is Ari's choice per machine and macOS offers no supported way to set it, so it
  # is reported, never judged.
  local style="unknown"
  [[ "${allowed}" == on\ * ]] && style="${allowed#on }"
  verdict ok configured -d "alert style='${style}' (System Settings > Notifications > terminal-notifier) | hook='${current}' stop='${stop}' guard='${guard}' notifier='${ARI_DOTFILES_NOTIFIER}'"
}

apply::claude_notifications() {
  run_mut "${HOME}/.config/claude/bin/initialize.sh"
}
