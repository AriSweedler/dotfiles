# Tests for claude.zsh — reclaude's id extraction.
# Only runs when OTTO_TEST__ZSH_PLUGINS_CLAUDE=true (sourced inside the plugin
# loader's function scope, like claude_parsers.test.zsh, so top-level `local` is ok).
[[ "$OTTO_TEST__ZSH_PLUGINS_CLAUDE" == "true" ]] || return 0

source "${0:h}/log.zsh"
source "${0:h}/claude.zsh"

local _pass=0 _fail=0

function _t() {  # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ((_pass++)); log::info "ok   | $name"
  else
    ((_fail++)); log::err "FAIL | $name | expected='$expected' actual='$actual'"
  fi
}

local _a="49ada35b-e27b-4b50-8726-d42d6af37205"
local _b="3082698e-0e53-44e3-b4c3-0f9f8ca445c5"

# --- resume_id_from_text: the exit hint Claude Code prints --------------------
_t "resume id: exit hint" "$_a" \
  "$(print -l 'Resume this session with:' "claude --resume $_a" 'at 17:47 ❯' | claude::resume_id_from_text)"
_t "resume id: last hint wins" "$_b" \
  "$(print -l "claude --resume $_a" 'noise' "claude --resume $_b" | claude::resume_id_from_text)"
_t "resume id: backticked hint in chat" "$_a" \
  "$(print -r -- "Run \`claude --resume $_a\` to continue" | claude::resume_id_from_text)"
_t "resume id: none → empty" "" \
  "$(print -l 'nothing here' 'claude --help' | claude::resume_id_from_text)"
print -l 'nothing here' | claude::resume_id_from_text >/dev/null 2>&1
_t "resume id: none → rc 1" "1" "$?"
_t "resume id: short id rejected" "" \
  "$(print -r -- 'claude --resume 49ada35b' | claude::resume_id_from_text)"

# --- project slug: Claude's ~/.claude/projects/<slug> derivation --------------
_t "project slug: / and . become -" "-Users-x--config-zsh" \
  "$(claude::project_slug /Users/x/.config/zsh)"

log::info "claude.test.zsh | pass=${_pass} fail=${_fail}"
(( _fail == 0 ))
