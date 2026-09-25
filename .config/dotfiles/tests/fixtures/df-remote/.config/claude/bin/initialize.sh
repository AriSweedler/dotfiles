#!/usr/bin/env bash
# Test double for ~/.config/claude/bin/initialize.sh: wires the notification hook and the
# headless-Chrome PreToolUse guard into ~/.claude/settings.json and nothing else (the real
# one also brew-installs terminal-notifier and merges into an existing settings.json).
set -u
mkdir -p "${HOME}/.claude"
jq -n --arg cmd "${HOME}/.config/claude/bin/notification-fire.sh" \
      --arg guard "${HOME}/.config/claude/bin/pretooluse-headless-chrome-guard.sh" \
  '{hooks: {Notification: [{hooks: [{type: "command", command: $cmd}]}],
            PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $guard, if: "Bash(*--headless*)", timeout: 5}]}]}}' \
  > "${HOME}/.claude/settings.json"
