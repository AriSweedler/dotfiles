#!/usr/bin/env bash
# Test double for ~/.config/claude/bin/initialize.sh: wires the notification hook into
# ~/.claude/settings.json and nothing else (the real one also brew-installs terminal-notifier).
set -u
mkdir -p "${HOME}/.claude"
jq -n --arg cmd "${HOME}/.config/claude/bin/notification-fire.sh" \
  '{hooks: {Notification: [{hooks: [{type: "command", command: $cmd}]}]}}' > "${HOME}/.claude/settings.json"
