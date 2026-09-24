#!/usr/bin/env zsh
#
# Claude Code PreToolUse hook (matcher: Bash). Refuses a Bash command that writes the
# clipboard with pbcopy unless it carries HANDOFF_CLIP_OK=1, which only the sanctioned
# path sets: /ari-clipboard-handoff's handoff.zsh --copy, run because Ari asked in that
# turn. Ari works several tasks at once; an unasked clipboard write destroys whatever he
# was carrying, and text that exists only on the clipboard is gone after one paste.
#
# Exit 2 blocks the tool call and feeds stderr back to Claude; exit 0 lets it through.
# The hook's JSON arrives on stdin; only .tool_input.command is matched, as a command
# token (bare or path-qualified), never a fragment of a longer name; settings.json also
# gates it with `if` so it only runs when the command mentions pbcopy at all.
#
# Install (per /ari-clipboard-handoff): copy or link next to the other hooks and add the
# settings.json entry:
#   cp "$HOME/.claude/skills/ari-clipboard-handoff/bin/pretooluse_bash_pbcopy_guard.sh" \
#      "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh" && chmod +x "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh"
#   PreToolUse: {"matcher":"Bash","hooks":[{"type":"command",
#     "command":"/Users/arisweedler/.config/claude/bin/pretooluse-pbcopy-guard.sh","if":"Bash(*pbcopy*)","timeout":5}]}
#
# Manual test (safe: `true` ignores its arguments, so the clipboard is never written even
# if the hook is not firing): echo '{"tool_input":{"command":"true pbcopy"}}' | zsh <this file>; echo $?
# Expect exit 2 and the message; with HANDOFF_CLIP_OK=1 in the command, exit 0.

set -u

main() {
  local input="" command=""
  IFS= read -r -d '' input || true
  # Match only the command text, so a description that mentions pbcopy never trips the guard.
  command="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)" || command="${input}"
  [[ -n "${command}" ]] || command="${input}"
  # pbcopy as a command token: bare or path-qualified (/usr/bin/pbcopy), never a fragment of a
  # longer name (xyz-pbcopy-abc, pbcopyish, pbcopy-wrapper, my.pbcopy).
  local pbcopy_cmd='(^|[^A-Za-z0-9_.-])pbcopy([^A-Za-z0-9_.-]|$)'
  [[ "${command}" =~ ${pbcopy_cmd} ]] || return 0
  [[ "${command}" == *HANDOFF_CLIP_OK=1* ]] && return 0

  cat >&2 <<'MSG'
Blocked: this command writes Ari's clipboard (pbcopy) and he did not ask for that in this turn. Print the text in the chat message instead, in a fenced code block, so it lives in the conversation history; Ari copies it himself. If he explicitly asks for a copy, use the sanctioned path, which saves the current clipboard first:
  zsh $HOME/.claude/skills/ari-clipboard-handoff/bin/handoff.zsh --copy --text '<text>'
MSG
  return 2
}

main "$@"
