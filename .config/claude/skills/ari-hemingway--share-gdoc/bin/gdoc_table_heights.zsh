#!/usr/bin/env zsh
# Measure every table in a Google Docs PDF export: rendered height per table in points, from the
# cell clip rectangles the export draws. Entrypoint for gdoc_table_heights.py.
#
# Usage: zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.zsh --pdf FILE.pdf
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/gdoc_table_heights.py" "${@}"
