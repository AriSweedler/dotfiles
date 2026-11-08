#!/usr/bin/env zsh
#
# Claude Code Stop hook → the same macOS notification as notification-fire.sh, at the end of
# every turn. A stop that another Stop hook is about to continue (stop_hook_active) is not the
# end of the turn, so it posts nothing.

set -u

readonly BIN_DIR="${0:A:h}"

main() {
  local input=""
  [[ -t 0 ]] || input="$(cat)"
  if [[ "$(print -r -- "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)" == "true" ]]; then
    return 0
  fi
  "${BIN_DIR}/notification-fire.sh" "Finished its turn" </dev/null
}

main "$@"
