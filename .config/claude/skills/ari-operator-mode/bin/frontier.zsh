#!/usr/bin/env zsh
# frontier.zsh — the one reader of state for operator mode: find the pane, then read nine sections in
# a fixed order through /ari-driving-remote's run.zsh and write one JSON into a fresh investigation
# folder. Read-only: nothing here writes to the tracker, a checkout or a pane beyond typing read
# commands. A pane busy with an agent's command (this capture's read, a fork's or a lane's run_log
# line) is waited for, within one capture-wide budget; anything else busy there is a cut-off. The two
# markers bin/pending.zsh and bin/away.zsh keep (his typed row, his announced absence) are read as the
# defaults of --pending and --away. One bd workspace can hold several sessions' epics, so a first read
# maps every open bead to its parent and every bd section keeps only the --scope epics and their
# descendants; without --scope, a workspace that holds an open epic is refused (exit 4) and nothing is
# written. Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
source "${SCRIPT_DIR:h}/lib/marker.zsh"

# --- Constants ---

readonly SECTIONS=(ready in_progress human blocked stale deferred host_git local_git health)
readonly HOST_SECTIONS=(ready in_progress human blocked stale deferred host_git)
readonly RUN_ZSH_DEFAULT="${SKILLS_DIR}/ari-driving-remote/bin/run.zsh"
readonly FOLD_WIDTH=60
readonly CAPTURE_LINES=500     # run.zsh dies of SIGPIPE on a capture of about 2000 lines (2026-10-30); 500 holds ~30 KB of base64
readonly LOCAL_TIMEOUT_S=10    # a git read on this Mac; fixed, so the whole capture stays under the Bash tool's 600 s
readonly AWAY_REASONS=(host_unreachable read_timed_out)   # the only cut-offs an announced absence explains; any other means the host answered
readonly RETRY_S="${FRONTIER_RETRY_S:-5}"   # between retries while the pane is busy with this session's own command; tests shorten it
readonly PROMPT_GLYPH_DEFAULT='❯'           # what the host's idle prompt line ends with; --prompt-end overrides it per host
readonly ID_PREFIX_DEFAULT='beads'          # the bead id prefix when no bd JSON list has shown one; --prefix overrides it
readonly SCOPE_STATUSES='open,in_progress,blocked,deferred'   # every status a briefing section can list; closed beads are never mapped
readonly EXIT_SCOPE_NEEDED=4
# Whether a bead id is one of the scope ids or descends from one: the id itself, a hierarchical child
# id (beads-xy9.6.1 under beads-xy9, which holds even when a parent between them is closed and so not
# mapped), or a parent chain through the map that reaches one (a bead joined to the epic after it was
# created keeps its own id). The limit stops a parent cycle.
readonly SCOPE_JQ_DEF='def inscope($e; $m): . as $id
  | [limit(64; $id | recurse(($m[.] // {}).parent // empty))]
  | any(.[]; . as $a | any($e[]; $a == . or ($a | startswith(. + "."))));'

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in jq git base64 gzip gunzip awk; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

help() {
  cat <<HELP
${c_green}frontier.zsh${c_rst} — read the operator-mode frontier (tracker, checkouts, pane) into one JSON

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --host-definition NAME --target PANE [OPTIONS]
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --local [OPTIONS]

${c_bold}Where the state lives:${c_rst}
  --host-definition NAME  /ari-driving-remote definition of the host that holds the tracker and checkout
  --target PANE           the pane to type read commands into: %N, W.P, or the full label (exact match)
  --local                 the tracker and checkout are on this machine; no pane is used

${c_bold}Options:${c_rst}
  --beads DIR             the bd workspace (default: ~/beads); every call is bd -C DIR, never cd
  --scope IDS             this session's epics, comma-separated (a loose bead it filed counts as one): every bd
                          section keeps only them and their descendants; 'all' keeps every bead. Without it, a
                          workspace that holds an open epic is refused with exit ${EXIT_SCOPE_NEEDED} and nothing is written
  --repo PATH             the project checkout on the host (default: none; host_git is skipped)
  --local-repo PATH       the project checkout on this machine (default: the current directory)
  --own-paths PATHS       the paths this session edited and has not committed, comma-separated, relative to the
                          checkout root; a dirty path among them is listed under own (default: none, so no dirty
                          path is this session's)
  --health CMD            the project's health command, recorded in the JSON, never run
  --root DIR              the investigation root (default: /tmp); the folder is DIR/operator-mode/<UTC stamp>
  --timeout S             seconds allowed per read (default: 45; at least 5); the whole capture gets S times the
                          number of host reads, and every retry sleep fits inside what is left
  --pending TEXT          the line a row of his left un-entered on the pane (the text after run.zsh's TYPED:), so a
                          pane holding or running it is reported as his row (row_pending, row_running), never as a
                          cut-off (default: what bin/pending.zsh set recorded for this session, if anything)
  --previous FILE         the last capture's frontier.json (default: the newest one under the root by this session on
                          this pane); a pane still busy with the same agent's command records own_command_persists
  --away TEXT             the absence Ari announced (the host itself going away: laptop taken, closed, off its network),
                          as the clause of his message that says so; recorded as away, so brief.zsh renders
                          host_unreachable and read_timed_out as the away line, not his P0 (default: what bin/away.zsh
                          set recorded for this session, if anything); a capture that reaches the host clears that
                          marker and records away_ended; one line, no question mark or backtick; refused with --local
  --prefix TEXT           the bead id prefix (default: the prefix of the first id a bd JSON list shows, else ${ID_PREFIX_DEFAULT});
                          only PREFIX-xxx tokens count as ids in bd's text output, so a hyphenated word never does
  --prompt-end TEXT       what the host's idle prompt line ends with (default: ${PROMPT_GLYPH_DEFAULT}; run.zsh --hosts prints each host's)
  --run-zsh PATH          the run.zsh to drive the pane with (default: the driving-remote skill's; tests pass a fake)
  -h, --help              this help

${c_bold}Output:${c_rst} key=value lines on stdout: dir= (the folder), json= (its frontier.json), cut_off=
  (none, or the reason); on exit ${EXIT_SCOPE_NEEDED} instead scope=needed, epics= (the open epics, comma-joined) and
  error= (why the bead map could not be read, when it could not). The JSON: captured_at, session,
  host_definition, pane, nickname, beads_dir, repo, local_repo, scope (null without --scope, else {epics, all,
  unknown: scope ids that are no open bead, error: why the bead map could not be read, so only hierarchical ids
  and each listed bead's own parent placed beads}), pending, pending_seen (true: his row was on the pane; false:
  the prompt was idle without it, so bin/pending.zsh clear is due; null: unknown or no row), away, away_ended
  (true when away was set and the host answered), typed (every command typed, in order), waited_s, cut_off
  (null, or {pane, reason, prompt_holds, busy_cmd, candidates, unread}), then ${(j:, :)SECTIONS}. In scope,
  human, blocked and stale keep only the scope's blocks of bd's text (the summary count rewritten), blockers
  counts only edges whose two beads are in scope, and deferred.count only the scope's beads. host_git and
  local_git hold {dirty, own, log}: own is the dirty entries --own-paths names. A section that could not be
  read holds {"error": "<why>"}; one the cut-off kept unread holds {"unread": true}. A crash after the reads
  still writes the JSON, the unfinished sections as errors.

${c_bold}Cut-off reasons:${c_rst} not_opted_in (77), other_session (76), busy or holds_text (75), no_pane (70),
  ambiguous_pane (the target matched more than one pane), read_timed_out (124: a read is still running
  in the pane), host_unreachable (255 from ssh), bad_definition (--list failed with another code: the
  definition or the flags, Claude's to fix), refused_text (1). Four more are waits, not his to clear: own_command (the pane ran an agent's command for the whole budget), own_command_persists (the
  previous capture by this session on this pane already waited on that same command), row_pending (his
  --pending row sits un-entered on the prompt), row_running (his --pending row is running). The host reads
  stop at the first cut-off; local_git and health still fill.

${c_bold}How a 75 is classified${c_rst}, in this order: the gate's words name copy mode or synchronized panes -> busy.
  Else the pane tail decides, the last prompt line's command joined across its wrapped lines: it is the
  --pending text -> row_pending (un-entered) or row_running; un-entered text that is not his row ->
  holds_text, whoever typed it; a running command that is an agent's (this capture's read, an earlier
  frontier read, a run_log-wrapped line, a BEADS_ACTOR=claude bd write; Ari types bare) -> retry every
  ${RETRY_S} s (FRONTIER_RETRY_S) within the budget, own_command when the budget is spent, own_command_persists
  when the previous capture already waited on it; anything else running -> busy.

${c_bold}Exit codes:${c_rst} 0 the JSON was written (cut off or not); 1 a missing prerequisite, a bad flag, an unreadable
  --previous, a bad --prefix, a --scope id that is not a bead id, --away empty or holding a newline, question
  mark or backtick, --away with --local, --timeout under 5, FRONTIER_RETRY_S not a positive integer, or
  CLAUDE_CODE_SESSION_ID unset without --local (run.zsh refuses every command without it);
  ${EXIT_SCOPE_NEEDED} no --scope while the workspace holds an open epic, or while the bead map could not be read: nothing
  is written.
  Host mode needs timeout or gtimeout (brew install coreutils): without one the fallback SIGKILLs the
  wrapper and can orphan an ssh that holds the pane lock.
HELP
}

# --- Parse ---

host_definition='' target='' local_mode=0 beads_dir='~/beads' repo='' local_repo="${PWD}"
health='' root_dir='/tmp' timeout_s=45 run_zsh="${RUN_ZSH_DEFAULT}" pending='' previous='' away=''
id_prefix='' prompt_glyph="${PROMPT_GLYPH_DEFAULT}" pending_given=0 away_given=0 scope_arg='' own_paths_arg=''
while (( $# > 0 )); do
  case "${1}" in
    --host-definition) host_definition="${2:?--host-definition requires a value}"; shift 2 ;;
    --target) target="${2:?--target requires a value}"; shift 2 ;;
    --local) local_mode=1; shift ;;
    --beads) beads_dir="${2:?--beads requires a value}"; shift 2 ;;
    --scope) scope_arg="${2:?--scope requires a value}"; shift 2 ;;
    --own-paths) own_paths_arg="${2:?--own-paths requires a value}"; shift 2 ;;
    --repo) repo="${2:?--repo requires a value}"; shift 2 ;;
    --local-repo) local_repo="${2:?--local-repo requires a value}"; shift 2 ;;
    --health) health="${2:?--health requires a value}"; shift 2 ;;
    --root) root_dir="${2:?--root requires a value}"; shift 2 ;;
    --timeout) timeout_s="${2:?--timeout requires a value}"; shift 2 ;;
    --pending) pending="${2:?--pending requires a value}"; pending_given=1; shift 2 ;;
    --prefix) id_prefix="${2:?--prefix requires a value}"; shift 2 ;;
    --prompt-end) prompt_glyph="${2:?--prompt-end requires a value}"; shift 2 ;;
    --previous) previous="${2:?--previous requires a value}"; shift 2 ;;
    --away) away="${2-}"; away_given=1; shift 2 ;;
    --run-zsh) run_zsh="${2:?--run-zsh requires a value}"; shift 2 ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown flag | flag='${1}'"; help; exit 1 ;;
  esac
done

# --- Massage ---

typeset -a scope_ids own_paths
scope_ids=("${(@s/,/)scope_arg}"); scope_ids=("${(@)scope_ids:#}")
own_paths=("${(@s/,/)own_paths_arg}"); own_paths=("${(@)own_paths:#}")
scope_all=false
if [[ "${scope_arg:l}" == all ]]; then scope_all=true; scope_ids=(); fi

# --- Validate ---

check_prerequisites || exit 1
for sid in "${scope_ids[@]}"; do
  if ! print -r -- "${sid}" | grep -qE '^[a-z]+-[a-z0-9]+(\.[0-9]+)*$'; then
    log::err "A --scope id is a bead id, or the whole value is all | scope_id='${sid}' scope='${scope_arg}'"
    exit 1
  fi
done
if [[ -n "${scope_arg}" && "${scope_all}" == false ]] && (( ${#scope_ids} == 0 )); then
  log::err "--scope names no bead | scope='${scope_arg}'"
  exit 1
fi
if (( ! local_mode )) && [[ -z "${host_definition}" || -z "${target}" ]]; then
  log::err "A host needs both flags, or pass --local | host_definition='${host_definition}' target='${target}'"
  exit 1
fi
if (( ! local_mode )) && [[ ! -r "${run_zsh}" ]]; then
  log::err "run.zsh not found | run_zsh='${run_zsh}'"
  exit 1
fi
if (( ! local_mode )) && [[ -z "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  log::err "CLAUDE_CODE_SESSION_ID is unset and run.zsh refuses every command without it | fix='run from a Claude Code session, or pass --local'"
  exit 1
fi
if [[ ! "${timeout_s}" == <-> ]] || (( timeout_s < 5 )); then
  log::err "Timeout must be an integer of at least 5 seconds | timeout_s='${timeout_s}'"
  exit 1
fi
if [[ ! "${RETRY_S}" == <-> ]] || (( RETRY_S < 1 )); then
  log::err "FRONTIER_RETRY_S must be an integer of at least 1 second | retry_s='${RETRY_S}'"
  exit 1
fi
if [[ -n "${previous}" && ! -r "${previous}" ]]; then
  log::err "--previous is not readable | previous='${previous}'"
  exit 1
fi
if (( away_given )) && [[ -z "${away}" ]]; then
  log::err "--away needs his words; to end an absence run bin/away.zsh clear | flag='--away'"
  exit 1
fi
if [[ "${away}" == *[$'\n?`']* ]]; then
  log::err "--away is one line with no question mark or backtick: the away line quotes it and has exactly one question mark | away='${away}'"
  exit 1
fi
if (( local_mode )) && [[ -n "${away}" ]]; then
  log::err "--away names a host that went away; --local has none | fix='drop --away'"
  exit 1
fi
if (( ! local_mode )) && ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
  log::err "Host mode needs timeout or gtimeout, or a stuck ssh keeps the pane lock | fix='brew install coreutils'"
  exit 1
fi
if [[ -n "${id_prefix}" ]] && ! print -r -- "${id_prefix}" | grep -qE '^[a-z]+$'; then
  log::err "The id prefix is lowercase letters | id_prefix='${id_prefix}'"
  exit 1
fi
readonly PENDING_MARKER="$(marker_path "${root_dir}" PENDING "${CLAUDE_CODE_SESSION_ID:-local}")"
readonly AWAY_MARKER="$(marker_path "${root_dir}" AWAY "${CLAUDE_CODE_SESSION_ID:-local}")"
if (( ! pending_given )) && pending="$(marker_show "${PENDING_MARKER}")"; then   # the row Brief typed for him, recorded by bin/pending.zsh set
  log::info "Pending row read from the marker | marker='${PENDING_MARKER}'"
fi
if (( ! away_given && ! local_mode )) && away="$(marker_show "${AWAY_MARKER}")"; then   # the absence he announced, recorded by bin/away.zsh set
  log::info "Absence read from the marker | marker='${AWAY_MARKER}'"
fi

# --- State ---

typeset -A section_json          # section -> JSON value
typeset -g pane_label='' nickname='' pane_bound='' cut_reason='' cut_prompt_holds='' cut_busy_cmd='' bd_missing=''
typeset -g capture_deadline=0 waited_s=0 prev_last_cmd='' prev_captured_at='' away_ended=false pending_seen=null json_written=0
typeset -ga unread=() typed=() candidates=() open_epics=()
# The bead map {id: {parent, issue_type}} from the first read, and why it could not be read. scope_jq_args
# carries the scope into every section's jq: $e the scope ids, $m the map, $scoped whether to filter.
typeset -g scope_beads_json='{}' scope_error='' scope_mapped=0 no_capture=0 own_paths_json='[]'
typeset -ga scope_jq_args=(--argjson e '[]' --argjson m '{}' --argjson scoped false)

# Reads set globals instead of printing: a command substitution would run them in a subshell and lose
# the exit code the caller needs. REPLY_OUT is stdout, REPLY_ERR stderr (or why a read failed),
# REPLY_RC the exit code.
typeset -g REPLY_OUT='' REPLY_ERR='' REPLY_RC=0

# --- Helpers ---

#######################################
# A JSON error value for a section.
# Arguments: $1 = why
#######################################
json_error() { jq -cn --arg e "${1}" '{error: $e}'; }

#######################################
# The last non-empty line of a text, trailing whitespace stripped.
# Arguments: $1 = text
#######################################
last_line() { print -r -- "${1}" | awk 'NF { sub(/[[:space:]]+$/, ""); l=$0 } END { print l }'; }

#######################################
# A path as the host's shell should see it: a leading ~ stays bare so the host expands it, the rest is
# double-quoted so spaces survive.
# Arguments: $1 = path
#######################################
host_path() {
  local p="${1}"
  if [[ "${p}" == '~' ]]; then print -r -- '~'; return 0; fi
  if [[ "${p}" == '~/'* ]]; then print -r -- "~/\"${p#\~/}\""; return 0; fi
  print -r -- "\"${p}\""
}

#######################################
# Run run.zsh with the given flags. Stdout and stderr land in separate files: the timeout lib opens
# its stderr file with O_TRUNC at its own offset, so sharing one file lets stderr overwrite the capture.
# Globals: run_zsh, host_definition, drive_timeout; sets REPLY_OUT, REPLY_ERR, REPLY_RC
# Arguments: $@ = flags after --host-definition NAME
#######################################
typeset -g drive_timeout=0
drive() {
  local out_file err_file rc=0
  out_file="$(mktemp)"; err_file="$(mktemp)"
  run_with_timeout $(( ${drive_timeout:-timeout_s} + 30 )) "${err_file}" zsh "${run_zsh}" --host-definition "${host_definition}" "$@" </dev/null >"${out_file}" || rc=$?
  REPLY_RC="${rc}"
  REPLY_OUT="$(<"${out_file}")"
  REPLY_ERR="$(<"${err_file}")"
  rm -f "${out_file}" "${err_file}"
}

#######################################
# Run one command on this machine, with the fixed local timeout.
# Globals: LOCAL_TIMEOUT_S; sets REPLY_OUT, REPLY_ERR, REPLY_RC
# Arguments: $@ = the command
#######################################
local_read() {
  local out_file err_file rc=0
  out_file="$(mktemp)"; err_file="$(mktemp)"
  run_with_timeout "${LOCAL_TIMEOUT_S}" "${err_file}" "$@" >"${out_file}" || rc=$?
  REPLY_RC="${rc}"
  REPLY_OUT="$(<"${out_file}")"
  REPLY_ERR="$(<"${err_file}")"
  rm -f "${out_file}" "${err_file}"
}

#######################################
# The REFUSED: line of a run.zsh answer, or empty.
# Arguments: $1 = run.zsh stdout; $2 = run.zsh stderr
#######################################
refused_line() { print -r -- "${1}"$'\n'"${2}" | awk '/^REFUSED:/ { l=$0 } END { print l }'; }

#######################################
# The command typed on the pane's last prompt line, from run.zsh's pane tail: the text after the prompt
# glyph on the last tail line that holds one, joined with its wrapped continuations (tmux wraps a long
# command over several lines and run.zsh captures without -J; a line is a continuation when the line
# before it ran the full pane width: the widest width in the tail, reached by at least two lines, so a
# tail whose longest line is the command itself joins nothing). Empty when no prompt line is in the tail.
# Globals: prompt_glyph
# Arguments: $1 = run.zsh stdout
#######################################
tail_prompt_command() {
  print -r -- "${1}" | awk -v g="${prompt_glyph}" '
    /^(TYPED|SENT|PANE|BIND|REFUSED|PANES):?/ || /^\[INFO\]/ { next }
    { n++; line[n]=$0; if (length($0) > w) { w=length($0); at=1 } else if (length($0) == w) at++ }
    END {
      if (at < 2) w=-1
      for (k = 1; k <= n; k++) {
        i=index(line[k], g)
        if (i) { c=substr(line[k], i + length(g)); sub(/^[[:space:]]+/, "", c); l=c; open=(length(line[k]) == w) }
        else if (open) { l = l line[k]; open=(length(line[k]) == w) }
      }
      sub(/[[:space:]]+$/, "", l); print l
    }'
}

#######################################
# The last pane line of a run.zsh answer, run.zsh's own lines and trailing whitespace dropped; a prompt
# line wrapped over several tail lines (each but the last at the full pane width, a width at least two
# tail lines reach) is one line here.
# Globals: prompt_glyph
# Arguments: $1 = run.zsh stdout
#######################################
tail_last_line() {
  print -r -- "${1}" | awk -v g="${prompt_glyph}" '
    /^(TYPED|SENT|PANE|BIND|REFUSED|PANES):?/ || /^\[INFO\]/ || !NF { next }
    { n++; line[n]=$0; if (length($0) > w) { w=length($0); at=1 } else if (length($0) == w) at++ }
    END {
      if (at < 2) w=-1
      for (k = 1; k <= n; k++) {
        if (index(line[k], g)) { l=line[k]; open=(length(line[k]) == w) }
        else if (open) { l = l line[k]; open=(length(line[k]) == w) }
        else l=line[k]
      }
      sub(/[[:space:]]+$/, "", l); print l
    }'
}

#######################################
# Whether a command on the pane is a Claude agent's, not Ari's: one this capture typed, an earlier
# frontier read (the marker recipe), any command wrapped in run_log (run.zsh wraps every command a
# session, fork or lane types; Ari types bare), or a BEADS_ACTOR=claude bd write (only Claude writes
# as claude). A bare bd or git command is Ari's.
# Globals: typed
# Arguments: $1 = the command text from the pane
#######################################
own_command_text() {
  local c="${1}" t
  [[ -z "${c}" ]] && return 1
  [[ "${c}" == *"printf 'Q%sQ'"* ]] && return 0
  for t in "${typed[@]}"; do
    [[ -n "${t}" && "${c}" == *"${t}"* ]] && return 0
  done
  case "${c}" in
    "run_log '"*|"BEADS_ACTOR=claude bd "*) return 0 ;;
  esac
  return 1
}

#######################################
# Classify a 75, in this order: the gate's words for copy mode or synchronized panes -> busy; else the
# pane tail decides, the last prompt line's command joined across its wrapped lines: his --pending row,
# the whole command and not a substring of a later one, un-entered or running is his row (row_pending,
# row_running, pending_seen true); un-entered text that is not his row is
# holds_text, whoever typed it (no wait clears it); a running agent's command (own_command_text) is a
# wait (retry), or own_command_persists when the previous capture by this session on this pane already
# waited on the same command; anything else running is busy.
# Globals: pending, prev_last_cmd, prev_captured_at; sets cut_reason, cut_prompt_holds
# Arguments: $1 = the REFUSED line; $2 = run.zsh stdout
# Returns: 0 when a reason was recorded; 3 when the pane runs an agent's command (retry)
#######################################
classify_75() {
  local refused="${1}" out="${2}" why last_cmd last_line busy_with
  why="${refused#REFUSED: }"; why="${why#* }"
  last_cmd="$(tail_prompt_command "${out}")"
  last_line="$(tail_last_line "${out}")"
  busy_with="${why}${last_cmd:+ (${last_cmd})}"
  case "${why}" in
    *"another caller is typing"*) ;;                      # a run.zsh holds the pane's lock: a fork or lane mid-type
    *"copy mode"*|*"synchronize-panes"*) cut_reason='busy'; cut_prompt_holds="${why}"; return 0 ;;
    *"not a shell"*)
      if [[ -n "${pending}" && "${last_cmd}" == "${pending}" ]]; then cut_reason='row_running'; cut_prompt_holds="${last_cmd}"; pending_seen=true; return 0; fi
      if ! own_command_text "${last_cmd}"; then cut_reason='busy'; cut_prompt_holds="${busy_with}"; return 0; fi ;;
    *"does not end in the prompt"*)
      if [[ -n "${pending}" && "${last_cmd}" == "${pending}" ]]; then cut_reason='row_pending'; cut_prompt_holds="${last_line}"; pending_seen=true; return 0; fi
      # the prompt line is the tail's last line: un-entered text, which no wait clears, whoever typed it
      if [[ -n "${last_cmd}" && "${last_line}" == *"${last_cmd}" ]]; then cut_reason='holds_text'; cut_prompt_holds="${last_line}"; return 0; fi
      if ! own_command_text "${last_cmd}"; then cut_reason='holds_text'; cut_prompt_holds="${last_line}"; return 0; fi ;;
    *) cut_reason='busy'; cut_prompt_holds="${why}"; return 0 ;;
  esac
  cut_busy_cmd="${last_cmd:-${why}}"
  if [[ -n "${prev_last_cmd}" && "${prev_last_cmd}" == "${cut_busy_cmd}" ]]; then   # the last capture already waited on this agent's command: not clearing, still not his
    cut_reason='own_command_persists'; cut_prompt_holds="${busy_with} since ${prev_captured_at}"; return 0
  fi
  cut_prompt_holds="${busy_with}"
  return 3
}

#######################################
# Turn a run.zsh exit code and its REFUSED line into a cut-off reason, and record it.
# Globals: sets cut_reason, cut_prompt_holds
# Arguments: $1 = exit code; $2 = run.zsh stdout; $3 = run.zsh stderr
# Returns: 0 when the code is a cut-off; 1 when it is not
#######################################
cut_off_from_rc() {
  local rc="${1}" out="${2}" err="${3}" refused tail_line
  refused="$(refused_line "${out}" "${err}")"
  tail_line="$(print -r -- "${out}" | awk '!/^(TYPED|SENT|PANE|BIND|REFUSED|PANES):?/ && !/^\[INFO\]/ && NF { sub(/[[:space:]]+$/, ""); l=$0 } END { print l }')"
  case "${rc}" in
    77) cut_reason='not_opted_in' ;;
    76) cut_reason='other_session' ;;
    75) cut_reason='busy'; cut_prompt_holds="${refused#REFUSED: }" ;;    # classify_75 handles a 75 on a read; this is the fallback
    70) cut_reason='no_pane'; cut_prompt_holds="${refused#REFUSED: }" ;;
    124) cut_reason='read_timed_out'; cut_prompt_holds="${tail_line}" ;;
    255) cut_reason='host_unreachable'; cut_prompt_holds="$(last_line "${err}")" ;;
    1) cut_reason='refused_text'; cut_prompt_holds="$(last_line "${err}")" ;;
    *) return 1 ;;
  esac
  log::warn "Cut off | reason='${cut_reason}' rc='${rc}' detail='${cut_prompt_holds}'"
  return 0
}

#######################################
# Find the pane in run.zsh's --list by exact match (the full label, ID=%N, or W.P) and record its full
# label and window name. The gate itself is run.zsh's, on the first typed read.
# Globals: target, pane_label, nickname, candidates, cut_reason, cut_prompt_holds
# Returns: 0 when exactly one pane matches; 1 when cut off (no_pane, ambiguous_pane, host_unreachable, bad_definition)
#######################################
find_pane() {
  drive --list
  if (( REPLY_RC != 0 )); then
    if (( REPLY_RC == 255 )); then cut_reason='host_unreachable'; else cut_reason='bad_definition'; fi   # only ssh's 255 is the host; anything else is the reader's call
    cut_prompt_holds="$(last_line "${REPLY_ERR}"$'\n'"${REPLY_OUT}")"
    pane_label="${target}"
    log::warn "run.zsh --list failed | rc='${REPLY_RC}' reason='${cut_reason}' detail='${cut_prompt_holds}'"
    return 1
  fi
  local -a lines
  lines=("${(@f)$(print -r -- "${REPLY_OUT}" | awk -v t="${target}" '
    /^(machine=[^|]+\|)?ID=%[0-9]+\|pane=[0-9]+\.[0-9]+ / {
      label=$1; tail="|pane=" t
      if (label == t || index(label, "ID=" t "|") > 0 || substr(label, length(label) - length(tail) + 1) == tail) print
    }')}")
  lines=("${(@)lines:#}")
  if (( ${#lines} == 0 )); then
    pane_label="${target}" cut_reason='no_pane'
    candidates=("${(@f)$(print -r -- "${REPLY_OUT}" | awk '/^(machine=[^|]+\|)?ID=%/ { print $1 }')}")
    candidates=("${(@)candidates:#}")
    log::warn "No pane matches the target | target='${target}' panes='${(j:, :)candidates}'"
    return 1
  fi
  if (( ${#lines} > 1 )); then
    pane_label="${target}" cut_reason='ambiguous_pane'
    candidates=("${(@)lines%% *}")
    log::warn "The target matches more than one pane | target='${target}' panes='${(j:, :)candidates}'"
    return 1
  fi
  pane_label="${lines[1]%% *}"
  # the rest of the line is 'mark bound=… command session: window -- title'
  pane_bound="$(print -r -- "${lines[1]}" | awk '{ for (i = 2; i <= NF; i++) if ($i ~ /^bound=/) { print $i; exit } }')"   # one short line # lint: ok
  nickname="$(print -r -- "${lines[1]}" | awk '{ s=index($0, ": "); if (!s) exit; rest=substr($0, s + 2); e=index(rest, " -- "); if (e) rest=substr(rest, 1, e - 1); print rest }')"   # one short line # lint: ok
  log::info "Pane found | pane='${pane_label}' nickname='${nickname}' ${pane_bound}"
  return 0
}

#######################################
# Read one command's output on the host through the pane, wrap-proof and rc-carrying. The marker is
# `@<nonce>@`, a fresh nonce per read, built on the host from pieces (so the echoed command never starts
# a line with it) and unknown to earlier reads, so payload still on the screen from a previous read is
# never swept into this one. The host prints <marker>BEGIN, then the command's output plus its exit
# code as a trailing __RC= line, gzipped, base64-encoded, folded, the marker on every line, then
# <marker>END <length>; the length catches a truncated capture. gzip keeps a 40 KB bd list inside one
# pane capture. A 75 goes through classify_75: this session's own command on the pane is retried every
# RETRY_S seconds while the capture budget lasts (capture_deadline), then recorded as own_command.
# Globals: target, timeout_s, typed; sets REPLY_OUT (decoded output), REPLY_RC (the host command's exit
#          code, or 1 when the capture was incomplete), REPLY_ERR (why, when it was)
# Arguments: $1 = the host command, one shell line
# Returns: 0 normally; 2 when run.zsh refused and a cut-off was recorded
#######################################
remote_read() {
  local host_cmd="${1}" nonce="${RANDOM}${RANDOM}"
  local marker="@${nonce}@" mlen=$(( ${#nonce} + 2 ))
  local cmd_line=" M=\$(printf 'Q%sQ' ${nonce} | tr Q @); printf '%sBEGIN\\n' \"\$M\"; { ${host_cmd}; printf '\\n__RC=%s\\n' \$?; } 2>&1 | gzip -c | base64 | tr -d '\\n' | awk -v m=\"\$M\" -v w=${FOLD_WIDTH} '{ n=length(\$0); for (i=1; i<=n; i+=w) print m substr(\$0, i, w); printf \"%sEND %d\\n\", m, n }'"
  typed+=("${host_cmd}")
  local waited=0 refused remaining nap cls
  while true; do
    remaining=$(( capture_deadline - SECONDS ))
    (( remaining < 5 )) && remaining=5                       # a read always gets its floor
    drive_timeout=$(( remaining < timeout_s ? remaining : timeout_s ))
    drive --target "${target}" --no-run-log --lines "${CAPTURE_LINES}" --timeout "${drive_timeout}" --cmd "${cmd_line}"
    (( REPLY_RC == 75 )) || break
    refused="$(refused_line "${REPLY_OUT}" "${REPLY_ERR}")"
    cls=0; classify_75 "${refused}" "${REPLY_OUT}" || cls=$?
    if (( cls != 3 )); then
      log::warn "Cut off | reason='${cut_reason}' rc='75' detail='${cut_prompt_holds}'"
      return 2
    fi
    if (( SECONDS >= capture_deadline )); then
      cut_reason='own_command'
      log::warn "Cut off | reason='${cut_reason}' detail='the pane stayed busy with this session's own command for the whole budget' busy_with='${cut_prompt_holds}'"
      return 2
    fi
    (( waited )) || log::info "waiting for the pane | pane='${pane_label}' busy_with='${cut_prompt_holds}' retry_s='${RETRY_S}' budget_left_s='$(( capture_deadline - SECONDS ))'"
    waited=1
    nap=$(( capture_deadline - SECONDS )); (( nap > RETRY_S )) && nap=${RETRY_S}; (( nap < 1 )) && nap=1
    sleep "${nap}"
    waited_s=$(( waited_s + nap ))
  done
  local raw="${REPLY_OUT}" rc="${REPLY_RC}"
  local end_line expected payload
  end_line="$(print -r -- "${raw}" | awk -v m="${marker}" 'index($0, m "END ") == 1 && $2 ~ /^[0-9]+$/ { l=$0 } END { print l }')"
  if (( rc == 124 )) && [[ -n "${end_line}" ]]; then   # the host finished and ssh dropped after; the stream is whole
    log::info "The read finished before run.zsh gave up; decoding it | rc='124'"
    rc=0
  fi
  if (( rc != 0 )) && cut_off_from_rc "${rc}" "${REPLY_OUT}" "${REPLY_ERR}"; then
    return 2
  fi
  if [[ -z "${end_line}" ]]; then
    REPLY_RC=1; REPLY_OUT=''
    REPLY_ERR="read did not finish in ${timeout_s}s; last line: $(last_line "${raw}")"
    log::warn "Read did not complete | rc='${rc}' last='$(last_line "${raw}")'"
    return 0
  fi
  expected="${end_line#*END }"
  payload="$(print -r -- "${raw}" | awk -v m="${marker}" -v l="${mlen}" '$0 == m "BEGIN" { on=1; p=""; next } index($0, m "END ") == 1 { on=0 } on && index($0, m) == 1 { p = p substr($0, l + 1) } END { printf "%s", p }')"
  if (( ${#payload} != expected )); then
    REPLY_RC=1; REPLY_OUT=''
    REPLY_ERR="truncated capture: ${#payload} of ${expected} encoded bytes reached this side"
    log::warn "Truncated capture | got='${#payload}' expected='${expected}'"
    return 0
  fi
  local decoded
  if ! decoded="$(print -r -- "${payload}" | base64 -d 2>/dev/null | gunzip -c 2>/dev/null)"; then
    REPLY_RC=1; REPLY_OUT=''; REPLY_ERR='the capture did not decode'
    log::warn "Capture did not decode | bytes='${#payload}'"
    return 0
  fi
  REPLY_RC="$(print -r -- "${decoded}" | awk '/^__RC=[0-9]+$/ { rc=substr($0, 6) } END { print (rc == "" ? 1 : rc) }')"
  REPLY_OUT="$(print -r -- "${decoded}" | awk '/^__RC=[0-9]+$/ { exit } { print }')"   # __RC is the last line, so awk reads to EOF # lint: ok
  REPLY_ERR=''
}

#######################################
# Read a command's output from wherever the tracker lives.
# Globals: local_mode; sets REPLY_OUT, REPLY_ERR, REPLY_RC
# Arguments: $1 = the command, as one shell line
# Returns: 2 when a cut-off was recorded (host only)
#######################################
read_cmd() {
  if (( local_mode )); then
    local_read zsh -c "${1}"
    return 0
  fi
  remote_read "${1}"
}

#######################################
# The JSON part of a command's output: bd can print a notice line before its --json body (and the
# host merges stderr), so everything before the first line opening a value is dropped.
# Arguments: $1 = raw output
#######################################
json_part() { print -r -- "${1}" | awk 'f || /^[[:space:]]*[\[{]/ { f=1; print }'; }

#######################################
# A bd JSON list trimmed to the fields a briefing uses and kept to the scope (a bead's own parent is a
# hop even when the map lacks it); [] for empty output; an error object when the command failed or did
# not print an array. Runs in a command substitution, so it sets no globals.
# Globals: scope_jq_args, SCOPE_JQ_DEF
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
bead_list() {
  local raw="${1}" rc="${2}" why="${3}" trimmed
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  if [[ -z "${raw//[[:space:]]/}" ]]; then print -r -- '[]'; return 0; fi
  if trimmed="$(json_part "${raw}" | jq -ce "${scope_jq_args[@]}" "${SCOPE_JQ_DEF}"'
      if type == "array" then [.[] | {id, title, priority, type: (.issue_type // .type // null), parent: (.parent // null), assignee: (.assignee // null), updated_at: (.updated_at // null)}]
        | if $scoped then map(select(. as $b | .id | inscope($e; $m + {($b.id): {parent: $b.parent}}))) else . end
      else error("not an array") end' 2>/dev/null)"; then
    print -r -- "${trimmed}"
    return 0
  fi
  json_error "not a JSON array: $(first_chars "${raw}")"
}

#######################################
# The first 160 characters of a text on one line, read to EOF (a head would SIGPIPE a large print).
# Arguments: $1 = text
#######################################
first_chars() { print -r -- "${1}" | awk '{ s = s $0 " " } END { print substr(s, 1, 160) }'; }

#######################################
# Lines of text as {text, ids}: ids are the PREFIX-xxx tokens that open a line, after an optional
# priority tag (bd human list prints `  beads-h1  title`, bd blocked prints `[P1] beads-bl1: title`), so
# a hyphenated word never counts. bd's summary line names a count (`(7)`, `(5 found)`); when it
# disagrees with the ids parsed, the section is an error: bd's text shape changed. A human bead whose
# block says `Status: deferred` is listed under deferred_ids, not ids: deferred is never a row. A block
# runs from its id line to the next; in scope, text keeps the lines before the first block (the summary
# count rewritten to the blocks kept) and the blocks whose id is in scope.
# Globals: id_prefix, scope_jq_args, SCOPE_JQ_DEF
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
text_section() {
  local raw="${1}" rc="${2}" why="${3}" prefix="${id_prefix:-${ID_PREFIX_DEFAULT}}"
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  jq -cn --arg t "${raw}" --arg p "${prefix}" "${scope_jq_args[@]}" "${SCOPE_JQ_DEF}"'
    ($t | split("\n")) as $lines
    | ("^\\s*(\\[P[0-9]\\]\\s+)?(?<id>" + $p + "-[a-z0-9]{2,}(\\.[0-9]+)*)(\\s|:|$)") as $re
    | "^[^a-z0-9]*[A-Za-z][A-Za-z -]*\\((?<n>[0-9]+)( found)?\\):?\\s*$" as $summary
    | [ $lines | to_entries[] | select(.value | test($re)) | {id: (.value | capture($re) | .id), i: .key} ] as $hits
    | [ range(0; $hits | length) as $k
        | $hits[$k] + {to: (if $k + 1 < ($hits | length) then $hits[$k + 1].i else ($lines | length) end)} ] as $blocks
    | ($lines | map(capture($summary)? | .n | tonumber) | first) as $count
    | ($hits | map(.id) | unique) as $all
    | ([ $blocks[] | select(any($lines[.i:.to][]; test("^\\s*Status:\\s*deferred"))) | .id ] | unique) as $deferred
    | if $count != null and $count != ($all | length)
      then {error: ("parsed " + ($all | length | tostring) + " ids of " + ($count | tostring) + " listed; the bd text shape changed"), text: $t}
      elif ($scoped | not) then {text: $t, ids: ($all - $deferred), deferred_ids: $deferred}
      else
        [ $all[] | select(inscope($e; $m)) ] as $keep
        | (if ($hits | length) > 0 then $lines[0:$hits[0].i] else $lines end
           | map(if test($summary) then sub("\\([0-9]+"; "(" + ($keep | length | tostring)) else . end)) as $head
        | [ $blocks[] | select(.id as $id | any($keep[]; . == $id)) | $lines[.i:.to][] ] as $kept
        | {text: ($head + $kept | join("\n")), ids: ($keep - $deferred), deferred_ids: ($keep - ($keep - $deferred))}
      end'
}

#######################################
# {text, ids, blockers}: blockers maps a blocking bead id to how many beads wait on it, from the
# "blocked by: <id>" or "Blocked by N open dependencies: [<id>]" lines bd blocked prints (a line that
# opens with those words; a title that mentions them is not one). In scope they are read from the kept
# blocks only, and a blocker outside the scope is dropped: an edge counts when both its beads are in scope.
# Globals: scope_jq_args, SCOPE_JQ_DEF
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
blocked_section() {
  local raw="${1}" rc="${2}" why="${3}" base blockers
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  base="$(text_section "${raw}" 0 '')"
  if print -r -- "${base}" | jq -e 'has("error")' >/dev/null 2>&1; then print -r -- "${base}"; return 0; fi
  blockers="$(print -r -- "${base}" | jq -r '.text' \
    | awk 'tolower($0) ~ /^[[:space:]]*blocked by/ { s=$0; sub(/^[[:space:]]*[Bb]locked by[^:\[]*[:\[][[:space:]]*/, "", s); gsub(/[\]\[]/, "", s); n=split(s, ids, /[,[:space:]]+/); for (i=1; i<=n; i++) if (ids[i] ~ /^[a-z]+-[a-z0-9.]+$/) c[ids[i]]++ } END { for (k in c) printf "%s\t%d\n", k, c[k] }' \
    | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries')"
  jq -cn --argjson b "${base}" --argjson k "${blockers}" "${scope_jq_args[@]}" "${SCOPE_JQ_DEF}"'
    $b + {blockers: (if $scoped then ($k | with_entries(select(.key | inscope($e; $m)))) else $k end)}'
}

#######################################
# A git section {dirty: [status lines], own: [the dirty lines whose path --own-paths names], log:
# [{hash, subject}]} from status --short and log --oneline. A path is the text after the two status
# columns (a rename's new path, quotes stripped); an untracked directory (`?? notes/`) is own when an
# own path lies under it.
# Globals: own_paths_json
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
git_section() {
  local raw="${1}" rc="${2}" why="${3}"
  if (( rc != 0 )); then json_error "${why:-"git failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  jq -cn --arg t "${raw}" --argjson own "${own_paths_json}" '($t | split("\n") | map(select(length > 0))) as $l
    | [$l[] | select(test("^[ MADRCU?!]{2} "))] as $dirty
    | {dirty: $dirty,
       own: [$dirty[] | select((.[3:] | sub("^.* -> "; "") | ltrimstr("\"") | rtrimstr("\"")) as $p
                               | any($own[]; . == $p or (($p | endswith("/")) and startswith($p))))],
       log: [$l[] | select(test("^[0-9a-f]{7,} ")) | capture("^(?<hash>[0-9a-f]+) (?<subject>.*)$")]}'
}

#######################################
# {count} from a bd JSON list, counting only the scope's beads in scope; 0 for empty output; an error
# object otherwise.
# Globals: scope_jq_args, SCOPE_JQ_DEF
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
count_section() {
  local raw="${1}" rc="${2}" why="${3}" n
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  if [[ -z "${raw//[[:space:]]/}" ]]; then print -r -- '{"count": 0}'; return 0; fi
  if n="$(json_part "${raw}" | jq -e "${scope_jq_args[@]}" "${SCOPE_JQ_DEF}"'
      if type == "array" then
        (if $scoped then map(select(. as $b | .id | inscope($e; $m + {($b.id): {parent: ($b.parent // null)}}))) else . end) | length
      else error("not an array") end' 2>/dev/null)"; then
    print -r -- "{\"count\": ${n}}"; return 0
  fi
  json_error "not a JSON array: $(first_chars "${raw}")"
}

#######################################
# Fill one host section from the tracker or the host checkout.
# Globals: section_json, beads_dir, repo
# Arguments: $1 = section name
# Returns: 2 when the read was cut off
#######################################
read_section() {
  local name="${1}" bd_dir cmd='' rc=0
  bd_dir="$(host_path "${beads_dir}")"
  case "${name}" in
    ready)       cmd="bd -C ${bd_dir} ready --exclude-label human --json" ;;
    in_progress) cmd="bd -C ${bd_dir} list -s in_progress --json" ;;
    human)       cmd="bd -C ${bd_dir} human list" ;;
    blocked)     cmd="bd -C ${bd_dir} blocked" ;;
    stale)       cmd="bd -C ${bd_dir} stale -d 14 -s in_progress" ;;
    deferred)    cmd="bd -C ${bd_dir} list -s deferred --json" ;;
    host_git)
      if [[ -z "${repo}" ]]; then section_json[$name]='{"skipped": "no --repo"}'; return 0; fi
      cmd="git -C $(host_path "${repo}") status --short && git -C $(host_path "${repo}") log -3 --oneline" ;;
  esac
  read_cmd "${cmd}" || rc=$?
  if (( rc == 2 )); then return 2; fi
  if [[ "${name}" == ready ]] && (( REPLY_RC == 127 )); then   # no bd on the host: the five other bd reads would fail the same way
    bd_missing="bd is not on the host's PATH, or ${beads_dir} is not a bd workspace (rc 127): $(last_line "${REPLY_OUT}")"
  fi
  case "${name}" in
    ready|in_progress) section_json[$name]="$(bead_list "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    human|stale)       section_json[$name]="$(text_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    blocked)           section_json[$name]="$(blocked_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    deferred)          section_json[$name]="$(count_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    host_git)          section_json[$name]="$(git_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
  esac
  if [[ "${name}" == ready && -n "${bd_missing}" ]]; then   # the read that found the precondition carries it too, so triage sees one cause for all six
    section_json[$name]="$(jq -cn --arg e "${bd_missing}" '{error: $e, precondition: true}')"
  fi
  log::info "Read section | section='${name}' rc='${REPLY_RC}'"
}

#######################################
# The first read: every bead in SCOPE_STATUSES as {id: {parent, issue_type}}, so a section can tell this
# session's beads from another session's in the same workspace. The host keeps only the id, parent and
# issue_type lines of bd's JSON, so a large workspace still fits one pane capture; the subshell keeps
# pipefail off his shell and carries bd's own exit code. Sets the globals directly: never call it in a
# command substitution.
# Globals: beads_dir; sets scope_beads_json, scope_error, scope_mapped, open_epics, id_prefix, bd_missing
# Returns: 2 when the read was cut off
#######################################
read_scope() {
  local bd_dir rc=0 parsed
  bd_dir="$(host_path "${beads_dir}")"
  read_cmd "( set -o pipefail; bd -C ${bd_dir} list -n 0 -s ${SCOPE_STATUSES} --json | awk '/\"(id|parent|issue_type)\": /' )" || rc=$?
  if (( rc == 2 )); then return 2; fi
  if (( REPLY_RC == 127 )); then   # no bd on the host: the six bd reads would fail the same way
    bd_missing="bd is not on the host's PATH, or ${beads_dir} is not a bd workspace (rc 127): $(last_line "${REPLY_OUT}")"
    scope_error="${bd_missing}"
    log::warn "bd is missing | detail='${bd_missing}'"
    return 0
  fi
  if (( REPLY_RC != 0 )); then
    scope_error="${REPLY_ERR:-"command failed (rc ${REPLY_RC}): $(last_line "${REPLY_OUT}")"}"
    log::warn "The bead map could not be read | detail='${scope_error}'"
    return 0
  fi
  parsed="$(print -r -- "${REPLY_OUT}" | jq -Rsc '[scan("\"(id|parent|issue_type)\": *\"([^\"]*)\"")]
    | reduce .[] as $f ({cur: null, beads: {}};
        if $f[0] == "id" then .cur = $f[1] | .beads[$f[1]] = {} elif .cur == null then . else .beads[.cur][$f[0]] = $f[1] end)
    | .beads')"
  scope_beads_json="${parsed}"
  scope_mapped=1
  open_epics=("${(@f)$(print -r -- "${parsed}" | jq -r 'to_entries[] | select(.value.issue_type == "epic") | .key' | sort)}")
  open_epics=("${(@)open_epics:#}")
  if [[ -z "${id_prefix}" ]]; then   # the first id pins the prefix for the text sections
    id_prefix="$(print -r -- "${parsed}" | jq -r '[keys[] | capture("^(?<p>[a-z]+)-")? | .p] | first // ""')"
    [[ -n "${id_prefix}" ]] && log::info "Id prefix learned | id_prefix='${id_prefix}'"
  fi
  log::info "Bead map read | beads='$(print -r -- "${parsed}" | jq 'length')' open_epics='${(j:,:)open_epics}'"
}

#######################################
# Whether this capture must be refused: no --scope, bd is there, and the workspace holds an open epic
# or could not be mapped (so it may hold one); another session's beads would otherwise become his rows.
# Globals: scope_arg, bd_missing, open_epics, scope_error
#######################################
is_scope_needed() {
  if [[ -n "${scope_arg}" ]]; then return 1; fi
  if [[ -n "${bd_missing}" ]]; then log::info "No --scope, but bd is missing: the capture carries the precondition"; return 1; fi
  if (( ${#open_epics} > 0 )); then log::warn "No --scope and the workspace holds open epics | open_epics='${(j:,:)open_epics}'"; return 0; fi
  if [[ -n "${scope_error}" ]]; then log::warn "No --scope and the bead map could not be read, so it may hold epics | detail='${scope_error}'"; return 0; fi
  log::info "No --scope and no open epic: the workspace is read whole"
  return 1
}

#######################################
# The jq arguments every section filters with, once the bead map is read.
# Globals: scope_ids, scope_all, scope_beads_json; sets scope_jq_args
#######################################
set_scope_args() {
  local scoped=false
  if [[ "${scope_all}" == false ]] && (( ${#scope_ids} > 0 )); then scoped=true; fi
  scope_jq_args=(--argjson e "$(json_strings "${scope_ids[@]}")" --argjson m "${scope_beads_json}" --argjson scoped "${scoped}")
  log::info "Scope set | scoped='${scoped}' scope_ids='${(j:,:)scope_ids}'"
}

#######################################
# Refuse an unscoped capture: nothing is written, and the open epics are printed for the one question.
# Globals: open_epics, scope_error; sets no_capture
#######################################
refuse_unscoped() {
  no_capture=1
  cat <<EOF
scope=needed
epics=${(j:,:)open_epics}
error=${scope_error}
EOF
  exit "${EXIT_SCOPE_NEEDED}"
}

#######################################
# The two sections that never need the pane.
# Globals: section_json, local_repo, health
#######################################
read_local_sections() {
  local_read git -C "${local_repo}" status --short
  local st_out="${REPLY_OUT}" st_rc="${REPLY_RC}" st_err="${REPLY_ERR}"
  local_read git -C "${local_repo}" log -3 --oneline
  if (( st_rc != 0 || REPLY_RC != 0 )); then
    section_json[local_git]="$(json_error "git failed: $(last_line "${st_err}"$'\n'"${REPLY_ERR}")")"
  else
    section_json[local_git]="$(git_section "${st_out}"$'\n'"${REPLY_OUT}" 0 '')"
  fi
  if [[ -n "${health}" ]]; then
    section_json[health]="$(jq -cn --arg c "${health}" '{command: $c, ran: false}')"
  else
    section_json[health]='{"command": null, "ran": false}'
  fi
}

#######################################
# Read the bead map, then the host sections in order; stop at the first cut-off and mark the rest
# unread (a cut-off on the map leaves all seven unread).
# Globals: section_json, unread, HOST_SECTIONS
# Returns: 4 when an unscoped capture must be refused (is_scope_needed)
#######################################
read_host_sections() {
  local name n rc=0 i=0
  read_scope || rc=$?
  if (( rc == 2 )); then
    unread=("${HOST_SECTIONS[@]}")
    for n in "${unread[@]}"; do section_json[$n]='{"unread": true}'; done
    return 0
  fi
  if is_scope_needed; then return "${EXIT_SCOPE_NEEDED}"; fi
  set_scope_args
  for name in "${HOST_SECTIONS[@]}"; do
    i=$(( i + 1 ))
    if [[ -n "${bd_missing}" && "${name}" != host_git ]]; then   # one precondition, one row: never five more typed reads
      section_json[$name]="$(jq -cn --arg e "${bd_missing}" '{error: $e, precondition: true}')"
      continue
    fi
    rc=0; read_section "${name}" || rc=$?
    if (( rc == 2 )); then
      unread=("${(@)HOST_SECTIONS[i,-1]}")
      for n in "${unread[@]}"; do section_json[$n]='{"unread": true}'; done
      return 0
    fi
  done
}

#######################################
# Every section value must be JSON, or the assembly would die with nothing written.
# Globals: section_json, SECTIONS
#######################################
validate_sections() {
  local name
  for name in "${SECTIONS[@]}"; do
    if [[ -z "${section_json[$name]:-}" ]] || ! print -r -- "${section_json[$name]}" | jq -e . >/dev/null 2>&1; then
      log::warn "Section was not JSON; recorded as an error | section='${name}' value='${section_json[$name]:-}'"
      section_json[$name]="$(json_error "the capture produced no JSON for this section")"
    fi
  done
}

#######################################
# A JSON array of strings from a zsh array (empty strings dropped).
# Arguments: $@ = the strings
#######################################
json_strings() {
  if (( $# == 0 )); then print -r -- '[]'; return 0; fi
  printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length > 0))'
}

# --- Logic ---

#######################################
# The last capture's wait on this pane by this session, so a pane still busy with the same agent's
# command records own_command_persists instead of waiting the whole budget again. Another session's
# or another pane's capture is never read.
# Globals: previous, root_dir, pane_label; sets prev_last_cmd, prev_captured_at
#######################################
read_previous() {
  local file="${previous}" session="${CLAUDE_CODE_SESSION_ID:-local}"
  if [[ -z "${file}" ]]; then
    local -a files
    files=("${(@f)$(ls -t "${root_dir}"/operator-mode/*/frontier.json 2>/dev/null || true)}")
    for file in "${files[@]}"; do
      [[ -n "${file}" ]] || continue
      jq -e --arg s "${session}" --arg p "${pane_label}" '.session == $s and .pane == $p' "${file}" >/dev/null 2>&1 && break
      file=''
    done
  fi
  [[ -n "${file}" && -r "${file}" ]] || return 0
  prev_last_cmd="$(jq -r '.cut_off | select(. != null and (.reason == "own_command" or .reason == "own_command_persists")) | .busy_cmd // ""' "${file}" 2>/dev/null || true)"
  if [[ -n "${prev_last_cmd}" ]]; then
    prev_captured_at="$(jq -r '.captured_at // ""' "${file}")"
    log::info "Previous capture waited on this pane | previous='${file}' busy_cmd='${prev_last_cmd}'"
  fi
  return 0
}

#######################################
# A fresh folder for this capture: the helper's stamp, suffixed when another capture took it this second.
# Globals: root_dir
#######################################
capture_dir() {
  local dir base i=1
  base="$(mk_investigation_dir "${root_dir}" operator-mode)"
  dir="${base}"
  while [[ -e "${dir}/frontier.json" ]]; do dir="${base}-${i}"; i=$(( i + 1 )); done
  mkdir -p "${dir}"
  print -r -- "${dir}"
}

#######################################
# The capture's scope: null without --scope (the workspace held no open epic), else {epics, all, unknown:
# the scope ids the bead map does not hold, error: why the map could not be read}. unknown is empty when
# the map was not read, so a cut-off never reports a typo.
# Globals: scope_arg, scope_ids, scope_all, scope_beads_json, scope_mapped, scope_error
#######################################
scope_value() {
  if [[ -z "${scope_arg}" ]]; then print -r -- 'null'; return 0; fi
  jq -cn --argjson e "$(json_strings "${scope_ids[@]}")" --argjson all "${scope_all}" --argjson m "${scope_beads_json}" \
    --argjson mapped "${scope_mapped}" --arg err "${scope_error}" \
    '{epics: $e, all: $all, unknown: (if $mapped == 1 then [$e[] | select(. as $x | $m | has($x) | not)] else [] end),
      error: (if $err == "" then null else $err end)}'
}

#######################################
# Assemble and write the capture. Called once by main, or by the EXIT trap when main died after the
# reads began (then the sections not yet gathered are errors, never a lost capture).
# Globals: section_json, cut_reason, cut_prompt_holds, cut_busy_cmd, candidates, unread, typed, waited_s,
#          pending, pending_seen, away, away_ended, pane_label, nickname; sets json_written
#######################################
write_json() {
  local cut_off='null'
  if [[ -n "${cut_reason}" ]]; then
    cut_off="$(jq -cn --arg p "${pane_label}" --arg r "${cut_reason}" --arg h "${cut_prompt_holds}" --arg b "${cut_busy_cmd}" \
      --argjson c "$(json_strings "${candidates[@]}")" --argjson u "$(json_strings "${unread[@]}")" \
      '{pane: $p, reason: $r, prompt_holds: (if $h == "" then null else $h end), busy_cmd: (if $b == "" then null else $b end), candidates: $c, unread: $u}')"
  fi
  local dir json_file json
  dir="$(capture_dir)"
  json_file="${dir}/frontier.json"
  json="$(jq -n \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg session "${CLAUDE_CODE_SESSION_ID:-local}" \
    --arg pane "${pane_label}" --arg nick "${nickname}" --arg hd "${host_definition:-local}" \
    --arg beads "${beads_dir}" --arg repo "${repo}" --arg lrepo "${local_repo}" --arg pending "${pending}" --arg away "${away}" \
    --argjson scope "$(scope_value)" --argjson pseen "${pending_seen}" --argjson aended "${away_ended}" \
    --argjson typed "$(json_strings "${typed[@]}")" --argjson waited "${waited_s}" --argjson cut "${cut_off}" \
    --argjson ready "${section_json[ready]}" --argjson in_progress "${section_json[in_progress]}" \
    --argjson human "${section_json[human]}" --argjson blocked "${section_json[blocked]}" \
    --argjson stale "${section_json[stale]}" --argjson deferred "${section_json[deferred]}" \
    --argjson host_git "${section_json[host_git]}" --argjson local_git "${section_json[local_git]}" \
    --argjson health "${section_json[health]}" \
    '{captured_at: $ts, session: $session, host_definition: $hd, pane: $pane,
      nickname: (if $nick == "" then null else $nick end), beads_dir: $beads,
      repo: (if $repo == "" then null else $repo end), local_repo: $lrepo, scope: $scope,
      pending: (if $pending == "" then null else $pending end), pending_seen: $pseen,
      away: (if $away == "" then null else $away end), away_ended: $aended,
      typed: $typed, waited_s: $waited, cut_off: $cut,
      ready: $ready, in_progress: $in_progress, human: $human, blocked: $blocked, stale: $stale,
      deferred: $deferred, host_git: $host_git, local_git: $local_git, health: $health}')"
  print -r -- "${json}" > "${json_file}"
  json_written=1
  log::info "Frontier written | json='${json_file}' cut_off='${cut_reason:-none}' typed='${#typed}' waited_s='${waited_s}'"
  cat <<EOF
dir=${dir}
json=${json_file}
cut_off=${cut_reason:-none}
EOF
}

#######################################
# The EXIT trap: a crash after the reads began still leaves a capture, every section not gathered an
# error naming the line that died, so seven host reads are never lost to one bad jq.
# Globals: reading_started, json_written, section_json
#######################################
typeset -g reading_started=0 crash_line=''
on_exit() {
  local rc=$? name
  (( reading_started && ! json_written && ! no_capture )) || return 0
  log::err "The reader crashed after the reads began; writing what it gathered | rc='${rc}' line='${crash_line:-?}'"
  for name in "${SECTIONS[@]}"; do
    [[ -n "${section_json[$name]:-}" ]] || section_json[$name]="$(json_error "the reader crashed before this section: line ${crash_line:-?}")"
  done
  validate_sections
  write_json || true
}
trap 'crash_line=${LINENO}' ERR
trap on_exit EXIT

#######################################
# The absence ends when the host answers: a capture with no cut-off, or one whose reason the absence
# does not explain (the pane refused, a read timed out mid-run is still the absence). The marker goes,
# so the next capture needs no --away, and the JSON says so.
# Globals: away, cut_reason, AWAY_MARKER; sets away_ended
#######################################
end_absence_if_host_answered() {
  [[ -n "${away}" ]] || return 0
  if [[ -n "${cut_reason}" ]] && (( ${AWAY_REASONS[(Ie)${cut_reason}]} )); then return 0; fi
  away_ended=true
  if marker_clear "${AWAY_MARKER}"; then log::info "The host answered: the absence ended | marker='${AWAY_MARKER}'"; else log::info "The host answered: the absence ended (no marker to clear)"; fi
}

#######################################
# Whether his typed row was seen: true when the cut-off was his row; false when the reads went through,
# so the prompt was idle without it (bin/pending.zsh clear is due); null otherwise.
# Globals: pending, cut_reason; sets pending_seen
#######################################
note_pending_seen() {
  [[ -n "${pending}" ]] || return 0
  [[ "${pending_seen}" == true ]] && return 0
  if [[ -z "${cut_reason}" ]]; then pending_seen=false; log::info "His typed row is gone from the prompt | hint='bin/pending.zsh clear'"; fi
}

main() {
  local name rc=0
  capture_deadline=$(( SECONDS + timeout_s * (${#HOST_SECTIONS} + 1) ))   # the bead map is one more read
  reading_started=1
  own_paths_json="$(json_strings "${own_paths[@]}")"
  if (( local_mode )); then
    pane_label='local'
    read_previous
    read_host_sections || rc=$?
  elif find_pane; then
    read_previous
    read_host_sections || rc=$?
  else
    unread=("${HOST_SECTIONS[@]}")
    for name in "${HOST_SECTIONS[@]}"; do section_json[$name]='{"unread": true}'; done
  fi
  if (( rc == EXIT_SCOPE_NEEDED )); then refuse_unscoped; fi
  read_local_sections
  validate_sections
  end_absence_if_host_answered
  note_pending_seen
  write_json
}

main
