# step claude_notifications — the Claude Code hooks initialize.sh wires: Notification →
# notification-fire.sh and the PreToolUse headless-Chrome guard; terminal-notifier resolves.
step::declare claude_notifications --group tools \
  --desc "Claude Code hooks wired: Notification → notification-fire.sh, PreToolUse guard → pretooluse-headless-chrome-guard.sh; terminal-notifier resolves"

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
  if [[ -z "${ARI_DOTFILES_NOTIFIER}" ]] || ! command -v "${ARI_DOTFILES_NOTIFIER}" >/dev/null 2>&1; then
    verdict fail notifier_missing -d "terminal-notifier not found (initialize.sh installs it)" -f "${CLI_NAME} apply claude_notifications"
    return 0
  fi
  verdict ok configured -d "hook='${current}' guard='${guard}' notifier='${ARI_DOTFILES_NOTIFIER}'"
}

apply::claude_notifications() {
  run_mut "${HOME}/.config/claude/bin/initialize.sh"
}
