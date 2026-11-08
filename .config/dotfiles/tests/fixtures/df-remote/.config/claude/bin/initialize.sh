#!/usr/bin/env bash
# Test double for ~/.config/claude/bin/initialize.sh: wires the notification hook, the Stop
# hook and the headless-Chrome PreToolUse guard into ~/.claude/settings.json and nothing else
# (the real one also installs terminal-notifier and merges into an existing settings.json).
set -u
mkdir -p "${HOME}/.claude"
jq -n --arg cmd "${HOME}/.config/claude/bin/notification-fire.sh" \
      --arg guard "${HOME}/.config/claude/bin/pretooluse-headless-chrome-guard.sh" \
      --arg stop "${HOME}/.config/claude/bin/stop-fire.sh" \
  '{hooks: {Notification: [{hooks: [{type: "command", command: $cmd}]}],
            Stop: [{hooks: [{type: "command", command: $stop}]}],
            PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $guard, if: "Bash(*--headless*)", timeout: 5}]}]}}' \
  > "${HOME}/.claude/settings.json"
