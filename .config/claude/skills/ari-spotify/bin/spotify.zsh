#!/usr/bin/env zsh
# Thin wrapper: the Spotify and setlist.fm commands live in concert-mcp (apps/concert-mcp of the homelab checkout).
# `teaser` and `setlist-find` are top-level subcommands there; everything else sits under `concert-mcp spotify`.
set -euo pipefail
export CONCERT_MCP_OPERATOR_NAME="${CONCERT_MCP_OPERATOR_NAME:-Ari}"
project="${CONCERT_MCP_HOME:-$HOME/homelab/apps/concert-mcp}"
case "${1:-}" in
  teaser|setlist-find) exec uv run --project "$project" concert-mcp "$@" ;;
  *) exec uv run --project "$project" concert-mcp spotify "$@" ;;
esac
