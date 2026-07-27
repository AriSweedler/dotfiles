# Tests for claude_parsers.zsh — vercmp, dispatch selection, pid-map parsers.
# Only runs when OTTO_TEST__ZSH_PLUGINS_CLAUDE_PARSERS=true (sourced inside
# the plugin loader's function scope, like log_rotate.test.zsh, so top-level
# `local` is ok).
[[ "$OTTO_TEST__ZSH_PLUGINS_CLAUDE_PARSERS" == "true" ]] || return 0

source "${0:h}/log.zsh"
source "${0:h}/claude_parsers.zsh"

local _pass=0 _fail=0

function _t() {  # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ((_pass++)); log::info "ok   | $name"
  else
    ((_fail++)); log::err "FAIL | $name | expected='$expected' actual='$actual'"
  fi
}

# --- vercmp: numeric, not lexicographic ------------------------------------
_t "vercmp: equal"            "0"   "$(claude::vercmp 2.1.220 2.1.220)"
_t "vercmp: less"             "-1"  "$(claude::vercmp 1.2.9 1.2.21)"
_t "vercmp: greater"          "1"   "$(claude::vercmp 1.2.21 1.2.9)"
_t "vercmp: short == padded"  "0"   "$(claude::vercmp 2.1 2.1.0)"
_t "vercmp: major wins"       "1"   "$(claude::vercmp 2.0.0 1.9.9)"

# --- dispatch: newest parser <= runtime version -----------------------------
function claude_parser__ttest__1_2_9()  { print -- "p-1.2.9 $*"; }
function claude_parser__ttest__1_2_21() { print -- "p-1.2.21 $*"; }

_t "dispatch: between → older"    "p-1.2.9 x"   "$(claude::dispatch ttest 1.2.11 x)"
_t "dispatch: above all → newest" "p-1.2.21 x"  "$(claude::dispatch ttest 1.2.99 x)"
_t "dispatch: exact match"        "p-1.2.9 x"   "$(claude::dispatch ttest 1.2.9 x)"
_t "dispatch: below all → oldest" "p-1.2.9 x"   "$(claude::dispatch ttest 1.0.0 x 2>/dev/null)"
_t "dispatch: unknown family rc"  "1"           "$(claude::dispatch nosuch 1.0.0 2>/dev/null; print -- $?)"

unfunction claude_parser__ttest__1_2_9 claude_parser__ttest__1_2_21

# --- session_from_pid fixtures ----------------------------------------------
local TMP; TMP="$(mktemp -d /tmp/claude_parsers.test.XXXXXX)"
export CLAUDE_PARSERS_SESSIONS_DIR="${TMP}/sessions"
export CLAUDE_PARSERS_PROJECTS_DIR="${TMP}/projects"
mkdir -p "${CLAUDE_PARSERS_SESSIONS_DIR}" "${CLAUDE_PARSERS_PROJECTS_DIR}/-proj"

# Direct (pre-daemon shape): sessionId is the displayed session.
print -r -- '{"pid":111,"sessionId":"aaaaaaaa-1111-1111-1111-111111111111","version":"2.1.220"}' \
  > "${CLAUDE_PARSERS_SESSIONS_DIR}/111.json"
# Parked client (2.1.x daemon shape): stale own sessionId + parkedJobId.
print -r -- '{"pid":222,"sessionId":"deadbeef-2222-2222-2222-222222222222","parkedJobId":"913f0d6f","version":"2.1.220"}' \
  > "${CLAUDE_PARSERS_SESSIONS_DIR}/222.json"
# The daemon-hosted job the client is attached to.
print -r -- '{"pid":333,"sessionId":"913f0d6f-3333-3333-3333-333333333333","jobId":"913f0d6f","kind":"bg","version":"2.1.220"}' \
  > "${CLAUDE_PARSERS_SESSIONS_DIR}/333.json"

_t "session v1: direct"     "aaaaaaaa-1111-1111-1111-111111111111" \
  "$(claude_parser__session_from_pid__1_0_0 111)"
_t "session v2.1: direct"   "aaaaaaaa-1111-1111-1111-111111111111" \
  "$(claude_parser__session_from_pid__2_1_0 111)"
_t "session v1: parked → stale (known limitation)" "deadbeef-2222-2222-2222-222222222222" \
  "$(claude_parser__session_from_pid__1_0_0 222)"
_t "session v2.1: parked → daemon job" "913f0d6f-3333-3333-3333-333333333333" \
  "$(claude_parser__session_from_pid__2_1_0 222)"
_t "session v2.1: missing pid rc" "1" \
  "$(claude_parser__session_from_pid__2_1_0 999 2>/dev/null; print -- $?)"
_t "dispatch: 2.1.220 routes to parked-aware parser" "913f0d6f-3333-3333-3333-333333333333" \
  "$(claude::dispatch session_from_pid 2.1.220 222)"
_t "dispatch: 1.5.0 routes to direct parser" "deadbeef-2222-2222-2222-222222222222" \
  "$(claude::dispatch session_from_pid 1.5.0 222)"

# --- version_for_pid ---------------------------------------------------------
_t "version_for_pid: from stamp" "2.1.220" "$(claude::version_for_pid 111)"

# --- pr_from_session fixtures --------------------------------------------------
local UUID="913f0d6f-3333-3333-3333-333333333333"
local JSONL="${CLAUDE_PARSERS_PROJECTS_DIR}/-proj/${UUID}.jsonl"
{
  print -r -- '{"type":"user","message":"hi"}'
  print -r -- '{"type":"pr-link","prNumber":100}'
  print -r -- '{"type":"assistant","message":"ok"}'
  print -r -- '{"type":"pr-link","prNumber":218482}'
  print -r -- '{"type":"user","message":"bye"}'
} > "${JSONL}"

_t "pr: most recent pr-link wins" "218482" "$(claude_parser__pr_from_session__1_0_0 "${UUID}")"
_t "pr: unknown uuid rc" "1" \
  "$(claude_parser__pr_from_session__1_0_0 00000000-0000-0000-0000-000000000000 2>/dev/null; print -- $?)"

# No pr-link at all → rc 1.
local UUID2="aaaaaaaa-1111-1111-1111-111111111111"
print -r -- '{"type":"user","message":"hi"}' > "${CLAUDE_PARSERS_PROJECTS_DIR}/-proj/${UUID2}.jsonl"
_t "pr: no binding rc" "1" \
  "$(claude_parser__pr_from_session__1_0_0 "${UUID2}" 2>/dev/null; print -- $?)"

unset CLAUDE_PARSERS_SESSIONS_DIR CLAUDE_PARSERS_PROJECTS_DIR
rm -rf "${TMP}"

log::info "claude_parsers.test.zsh | pass=${_pass} fail=${_fail}"
(( _fail == 0 ))
