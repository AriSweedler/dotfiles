#!/usr/bin/env zsh
# Entrypoint for example.py: puts the shared python lib on PYTHONPATH, then runs it.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${SCRIPT_DIR:h:h}"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 "${SCRIPT_DIR}/example.py" "${@}"
