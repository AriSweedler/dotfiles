#!/usr/bin/env zsh
# Entrypoint for cluster_definitions.py: puts the shared python lib on PYTHONPATH, then runs it.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/cluster_definitions.py" "${@}"
