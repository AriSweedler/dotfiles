#!/usr/bin/env zsh
# Asides as tabs: split `# Aside n:` sections out of a draft before upload, or rebuild them as tabs on
# the published Doc and link each `([aside n ℹ️](#aside-n))` marker to its tab. Entrypoint for
# gdoc_asides.py; gdoc_publish.zsh runs both modes on every publish.
#
# Usage: zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.zsh --split --file DRAFT.md --body-out BODY.md [--force]
#        zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.zsh --rebuild --file DRAFT.md --doc ID [--dry-run] [--first-tab-title T] [--bookmarks --script-id ID]
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/gdoc_asides.py" "${@}"
