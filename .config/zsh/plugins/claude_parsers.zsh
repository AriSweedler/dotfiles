# claude_parsers.zsh — version-dispatched parsers for Claude Code's private
# interfaces (process names, ~/.claude/sessions pid map, session JSONLs).
#
# Claude updates change these interfaces without notice: 2.1.x's daemon
# rewrote the pid→session semantics and broke Hyper+Q. Every version-sensitive
# chunk lives here as a family of parser functions:
#
#   claude_parser__<family>__<M>_<m>_<p>
#
# where <M>_<m>_<p> is the oldest claude version the parser is written
# against. claude::dispatch runs the newest parser whose version is <= the
# running claude's version. With parsers at 1.2.9 and 1.2.21: runtime 1.2.11
# dispatches to 1.2.9, runtime 1.2.99 dispatches to 1.2.21. A runtime older
# than every parser falls back to the oldest, with a warning.
#
# Parsers log via log.zsh and print their result to stdout; non-zero return
# on any failure. Paths are overridable for tests:
#   CLAUDE_PARSERS_SESSIONS_DIR   (default ~/.claude/sessions)
#   CLAUDE_PARSERS_PROJECTS_DIR   (default ~/.claude/projects)

# --- Version plumbing ---

# Numeric dotted-version compare; prints -1/0/1. Missing parts are 0, so
# "2.1" == "2.1.0". Numeric, not lexicographic: 1.2.9 < 1.2.21.
function claude::vercmp() {
  local -a a=(${(s:.:)1}) b=(${(s:.:)2})
  local i x y
  for (( i=1; i <= (${#a} > ${#b} ? ${#a} : ${#b}); i++ )); do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    (( x < y )) && { print -- "-1"; return 0; }
    (( x > y )) && { print -- "1"; return 0; }
  done
  print -- "0"
}

function claude::installed_version() {
  local v
  v="$(command claude --version 2>/dev/null | awk '{print $1; exit}' || true)"
  if [[ ! "${v}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    log::debug "Cannot read installed claude version | raw='${v}'"
    return 1
  fi
  print -- "${v}"
}

# Version of the claude process behind <pid>, from its own pid map stamp.
# More precise than the installed CLI: the focused process may be older.
function claude::version_for_pid() {
  local pid="${1:?claude::version_for_pid requires a pid}"
  local f="${CLAUDE_PARSERS_SESSIONS_DIR:-${HOME}/.claude/sessions}/${pid}.json"
  local v=""
  [[ -r "${f}" ]] && v="$(jq -r '.version // empty' "${f}" 2>/dev/null || true)"
  if [[ "${v}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    print -- "${v}"
    return 0
  fi
  log::debug "No per-pid version; falling back | pid='${pid}'"
  claude::best_known_version
}

# Best-effort runtime version when there's no pid to key off. Never fails:
# newest stamp in the pid map files (fast), else `claude --version` (slow,
# needs claude on PATH — not guaranteed under karabiner), else 0.0.0 so
# dispatch falls back to the oldest parser.
function claude::best_known_version() {
  local dir="${CLAUDE_PARSERS_SESSIONS_DIR:-${HOME}/.claude/sessions}"
  local -a maps=("${dir}"/*.json(N))
  local v=""
  if (( ${#maps} > 0 )); then
    v="$(jq -r '.version // empty' "${maps[@]}" 2>/dev/null \
      | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
  fi
  if [[ ! "${v}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    v="$(claude::installed_version)" || v="0.0.0"
  fi
  print -- "${v}"
}

# --- Dispatch ---

# claude::dispatch <family> <runtime-version> [parser args...]
function claude::dispatch() {
  local family="${1:?claude::dispatch requires a family}"
  local version="${2:?claude::dispatch requires a version}"
  shift 2

  local -a fns
  fns=(${(k)functions[(I)claude_parser__${family}__[0-9]*]})
  if (( ${#fns} == 0 )); then
    log::err "No parsers registered | family='${family}'"
    return 1
  fi

  local fn ver best="" best_ver=""
  for fn in "${fns[@]}"; do
    ver="${${fn#claude_parser__${family}__}//_/.}"
    [[ "$(claude::vercmp "${ver}" "${version}")" == "1" ]] && continue
    if [[ -z "${best}" || "$(claude::vercmp "${ver}" "${best_ver}")" == "1" ]]; then
      best="${fn}"; best_ver="${ver}"
    fi
  done

  if [[ -z "${best}" ]]; then
    for fn in "${fns[@]}"; do
      ver="${${fn#claude_parser__${family}__}//_/.}"
      if [[ -z "${best}" || "$(claude::vercmp "${ver}" "${best_ver}")" == "-1" ]]; then
        best="${fn}"; best_ver="${ver}"
      fi
    done
    log::warn "Runtime older than every parser; using oldest | family='${family}' version='${version}' parser='${best}'"
  fi

  log::debug "Parser dispatched | family='${family}' version='${version}' parser='${best}'"
  "${best}" "$@"
}

# --- family: pid_from_tty — tty short name (ttys005) → pid of the claude client ---

# The REPL is a process literally named `claude` on the pane tty. Still true
# in 2.1.x, where the on-tty process is the thin daemon client. macOS
# pgrep -t is broken for native tty names; parse `ps -t` instead.
function claude_parser__pid_from_tty__1_0_0() {
  local tty_short="${1:?pid_from_tty requires a tty (e.g. ttys005)}"
  local pid
  pid="$(ps -t "${tty_short}" -o pid=,command= 2>/dev/null \
    | awk '{ cmd=$2; sub(".*/", "", cmd); if (cmd == "claude") print $1 }' \
    | head -1 || true)"
  if [[ -z "${pid}" ]]; then
    log::err "No claude process on tty | tty='${tty_short}'"
    return 1
  fi
  print -- "${pid}"
}

# --- family: session_from_pid — claude pid → session UUID ---

# ~/.claude/sessions/<pid>.json names the displayed session directly.
function claude_parser__session_from_pid__1_0_0() {
  local pid="${1:?session_from_pid requires a pid}"
  local f="${CLAUDE_PARSERS_SESSIONS_DIR:-${HOME}/.claude/sessions}/${pid}.json"
  if [[ ! -r "${f}" ]]; then
    log::err "Claude session file missing | session_file='${f}'"
    return 1
  fi
  local uuid
  uuid="$(jq -r '.sessionId // empty' "${f}" 2>/dev/null || true)"
  if [[ -z "${uuid}" ]]; then
    log::err "No sessionId in claude session file | session_file='${f}'"
    return 1
  fi
  print -- "${uuid}"
}

# 2.1.x daemon: after a /resume, the on-tty client attaches to a daemon-hosted
# job. Its own pid map entry keeps a stale, never-used sessionId and records
# the attachment as parkedJobId; the job's own pid map entry (kind=bg,
# jobId=<parkedJobId>) carries the sessionId whose JSONL is actually written.
# 2_1_0 is a best-effort boundary for when the daemon landed — refine it if an
# older 2.x install misroutes.
function claude_parser__session_from_pid__2_1_0() {
  local pid="${1:?session_from_pid requires a pid}"
  local dir="${CLAUDE_PARSERS_SESSIONS_DIR:-${HOME}/.claude/sessions}"
  local f="${dir}/${pid}.json"
  if [[ ! -r "${f}" ]]; then
    log::err "Claude session file missing | session_file='${f}'"
    return 1
  fi

  local parked
  parked="$(jq -r '.parkedJobId // empty' "${f}" 2>/dev/null || true)"
  if [[ -z "${parked}" ]]; then
    claude_parser__session_from_pid__1_0_0 "${pid}"
    return
  fi

  log::debug "Client parked; following daemon job | pid='${pid}' parked_job='${parked}'"
  local -a maps=("${dir}"/*.json(N))
  local uuid=""
  if (( ${#maps} > 0 )); then
    uuid="$(jq -r --arg job "${parked}" 'select(.jobId == $job) | .sessionId // empty' \
      "${maps[@]}" 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "${uuid}" ]]; then
    log::err "Parked job has no session entry | pid='${pid}' parked_job='${parked}' sessions_dir='${dir}'"
    return 1
  fi
  print -- "${uuid}"
}

# --- family: pr_from_session — session UUID → bound PR number ---

# Most recent {"type":"pr-link","prNumber":N} record in the session's JSONL
# under ~/.claude/projects/<project>/<uuid>.jsonl (written by /pr's
# record-pr-link.zsh). Format unchanged through 2.1.x.
function claude_parser__pr_from_session__1_0_0() {
  local uuid="${1:?pr_from_session requires a session uuid}"
  local projects="${CLAUDE_PARSERS_PROJECTS_DIR:-${HOME}/.claude/projects}"
  local jsonl
  jsonl="$(find "${projects}" -maxdepth 2 -name "${uuid}.jsonl" -type f 2>/dev/null | head -1 || true)"
  if [[ -z "${jsonl}" ]]; then
    log::err "No session file found | uuid='${uuid}' projects_dir='${projects}'"
    return 1
  fi
  log::debug "Session file | jsonl='${jsonl}'"

  # Reverse-walk + grep -m1: stops at the most recent pr-link record
  # regardless of file size. `|| true` swallows the SIGPIPE that grep -m1
  # forces on tail -r under `set -o pipefail`.
  local pr
  pr="$(tail -r "${jsonl}" 2>/dev/null \
    | grep -m1 '"type":"pr-link"' \
    | jq -r '.prNumber // empty' 2>/dev/null || true)"
  if [[ -z "${pr}" ]]; then
    # Forked sessions deliberately not handled: claude UI may show a PR for
    # them (probably from in-memory state inherited at fork time), but we want
    # the bail to surface that this session's own JSONL has no binding.
    local forked_from
    forked_from="$(head -1 "${jsonl}" 2>/dev/null \
      | jq -r '.forkedFrom.sessionId // empty' 2>/dev/null || true)"
    log::err "no active PR | uuid='${uuid}' jsonl='${jsonl}' forked_from='${forked_from:-<none>}'"
    return 1
  fi
  print -- "${pr}"
}
