#!/usr/bin/env zsh
# Image findings for a Doc read, and the Drive-link and image-link patterns, from the Python the aside
# verify read uses. Entrypoint for gdoc_image_checks.py; gdoc_finish.zsh calls it. Read-only.
#
# Usage: zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_image_checks.zsh --doc-json FILE
#        zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_image_checks.zsh --constant image-link-prefix|drive-link-pattern
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib:${SKILLS_DIR}/ari-hemingway--lib/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/gdoc_image_checks.py" "${@}"
