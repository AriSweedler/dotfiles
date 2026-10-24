#!/bin/bash
#
# Picks a random Rocket League quickchat from
# ~/.claude/state/rocket_league/quickchats.txt and prints it with two emoji
# bookends. Used as a notification fallback message and as a standalone CLI
# toy.
#
# Exits 1 (with empty stdout) if the quickchats file is missing or empty.

set -u

readonly QUICKCHATS="${HOME}/.claude/state/rocket_league/quickchats.txt"

main() {
  [[ -f "${QUICKCHATS}" ]] || return 1
  local chat
  chat=$(sort -R "${QUICKCHATS}" | head -n 1)
  [[ -n "${chat}" ]] || return 1

  local shuffled left right
  shuffled=$(printf '🚗\n⚽\n🚀\n🏆\n' | sort -R)
  left=$(printf '%s\n' "${shuffled}" | sed -n '1,2p' | tr -d '\n')
  right=$(printf '%s\n' "${shuffled}" | sed -n '3,4p' | tr -d '\n')
  printf '%s %s %s\n' "${left}" "${chat}" "${right}"
}

main "$@"
