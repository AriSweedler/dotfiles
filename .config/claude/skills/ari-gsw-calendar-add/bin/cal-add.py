#!/usr/bin/env bash
# Thin wrapper: the policy lives in concert-mcp (apps/concert-mcp of the homelab checkout). Same flags, same
# JSON-on-stdin form, same FIX / NO_REPLY / NOT SENT contract as the script this replaced; docs/migration.md there.
export CONCERT_MCP_OPERATOR_NAME="${CONCERT_MCP_OPERATOR_NAME:-Ari}"
exec uv run --project "${CONCERT_MCP_HOME:-$HOME/homelab/apps/concert-mcp}" concert-mcp add --concert "$@"
