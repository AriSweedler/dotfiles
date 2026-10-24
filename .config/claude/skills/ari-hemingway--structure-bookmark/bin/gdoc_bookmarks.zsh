#!/usr/bin/env zsh
# Bookmarks in a published Google Doc: `[text](#bm-<slug>)` puts a bookmark on the text, `[text](#goto-<slug>)`
# links to it, and every aside marker is an implicit target for its tab's return links. Entrypoint for
# gdoc_bookmarks.py; gdoc_publish.zsh runs --check-setup then --apply after every publish.
#
# Usage: zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --check-setup
#        zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --configure --script-id ID [--deployment-id ID]
#        zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc ID_OR_URL --file DRAFT.md [--dry-run]
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers. The
# hemingway lib holds the Docs helpers this script shares with gdoc_asides.py.
readonly SKILLS_DIR="${HOME}/.claude/skills"
export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib:${SKILLS_DIR}/ari-hemingway--lib/lib${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${SCRIPT_DIR}/gdoc_bookmarks.py" "${@}"
