#!/usr/bin/env zsh
# Entrypoint for bead_autolink.py, the MessageDisplay hook that turns a bare bead id in Claude's
# message into its link on screen. Claude Code runs it per batch of displayed lines, with the hook
# payload on stdin; see bead_autolink.py for the contract.
# Hook entry: zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_autolink.zsh --workspace PREFIX=DIR
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/bead_autolink.py" "${@}"
