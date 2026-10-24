#!/usr/bin/env zsh
# run_with_timeout's canonical home is ari-skill-shellscripts/lib/run_with_timeout.zsh.
# This shim re-sources it so existing loaders keep working from one source of truth.
# Source it; do not execute.

# Through the symlink farm, not a hop from ${0:A}: skills are spread across dotfiles tiers.
source "${HOME}/.claude/skills/ari-skill-shellscripts/lib/run_with_timeout.zsh"
