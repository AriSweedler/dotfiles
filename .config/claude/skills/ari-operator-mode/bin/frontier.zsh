#!/usr/bin/env zsh
# frontier.zsh — the one reader of state for operator mode: find the pane, then read nine sections in
# a fixed order through /ari-driving-remote's run.zsh and write one JSON into a fresh investigation
# folder. Read-only: nothing here writes to the tracker, a checkout or a pane beyond typing read
# commands. Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --help

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

# --- Constants ---

readonly SECTIONS=(ready in_progress human blocked stale deferred host_git local_git health)
readonly HOST_SECTIONS=(ready in_progress human blocked stale deferred host_git)
readonly RUN_ZSH_DEFAULT="${SKILLS_DIR}/ari-driving-remote/bin/run.zsh"
readonly FOLD_WIDTH=60
readonly CAPTURE_LINES=500     # run.zsh dies of SIGPIPE on a capture of about 2000 lines (2026-10-30); 500 holds ~30 KB of base64

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in jq git base64 awk; do
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
  --repo PATH             the project checkout on the host (default: none; host_git is skipped)
  --local-repo PATH       the project checkout on this machine (default: the current directory)
  --health CMD            the project's health command, recorded in the JSON, never run
  --root DIR              the investigation root (default: /tmp); the folder is DIR/operator-mode/<UTC stamp>
  --timeout S             seconds allowed per read (default: 45; at least 5)
  --run-zsh PATH          the run.zsh to drive the pane with (default: the driving-remote skill's; tests pass a fake)
  -h, --help              this help

${c_bold}Output:${c_rst} key=value lines on stdout: dir= (the folder), json= (its frontier.json), cut_off=
  (none, or the reason). The JSON: captured_at, session, host_definition, pane, nickname, beads_dir,
  repo, local_repo, typed (every command typed, in order), cut_off (null, or {pane, reason,
  prompt_holds, candidates, unread}), then ${(j:, :)SECTIONS}. A section that could not be read
  holds {"error": "<why>"}; one the cut-off kept unread holds {"unread": true}.

${c_bold}Cut-off reasons:${c_rst} not_opted_in (77), other_session (76), busy or holds_text (75), no_pane (70),
  ambiguous_pane (the target matched more than one pane), read_timed_out (124: a read is still running
  in the pane), host_unreachable (255, or --list failed), refused_text (1). The host reads stop at the
  first cut-off; local_git and health still fill.

${c_bold}Exit codes:${c_rst} 0 the JSON was written (cut off or not); 1 a missing prerequisite or bad flag.
  CLAUDE_CODE_SESSION_ID must be set unless --local: run.zsh refuses every command without it.
  Without timeout/gtimeout the fallback SIGKILLs the wrapper and can orphan an ssh that holds the
  pane lock; a Mac wants coreutils (gtimeout).
HELP
}

# --- Parse ---

host_definition='' target='' local_mode=0 beads_dir='~/beads' repo='' local_repo="${PWD}"
health='' root_dir='/tmp' timeout_s=45 run_zsh="${RUN_ZSH_DEFAULT}"
while (( $# > 0 )); do
  case "${1}" in
    --host-definition) host_definition="${2:?--host-definition requires a value}"; shift 2 ;;
    --target) target="${2:?--target requires a value}"; shift 2 ;;
    --local) local_mode=1; shift ;;
    --beads) beads_dir="${2:?--beads requires a value}"; shift 2 ;;
    --repo) repo="${2:?--repo requires a value}"; shift 2 ;;
    --local-repo) local_repo="${2:?--local-repo requires a value}"; shift 2 ;;
    --health) health="${2:?--health requires a value}"; shift 2 ;;
    --root) root_dir="${2:?--root requires a value}"; shift 2 ;;
    --timeout) timeout_s="${2:?--timeout requires a value}"; shift 2 ;;
    --run-zsh) run_zsh="${2:?--run-zsh requires a value}"; shift 2 ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown flag | flag='${1}'"; help; exit 1 ;;
  esac
done

# --- Validate ---

check_prerequisites || exit 1
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

# --- State ---

typeset -A section_json          # section -> JSON value
typeset -g pane_label='' nickname='' cut_reason='' cut_prompt_holds=''
typeset -ga unread=() typed=() candidates=()

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
# Globals: run_zsh, host_definition, timeout_s; sets REPLY_OUT, REPLY_ERR, REPLY_RC
# Arguments: $@ = flags after --host-definition NAME
#######################################
drive() {
  local out_file err_file rc=0
  out_file="$(mktemp)"; err_file="$(mktemp)"
  run_with_timeout $(( timeout_s + 30 )) "${err_file}" zsh "${run_zsh}" --host-definition "${host_definition}" "$@" </dev/null >"${out_file}" || rc=$?
  REPLY_RC="${rc}"
  REPLY_OUT="$(<"${out_file}")"
  REPLY_ERR="$(<"${err_file}")"
  rm -f "${out_file}" "${err_file}"
}

#######################################
# Run one command on this machine with the timeout.
# Globals: timeout_s; sets REPLY_OUT, REPLY_ERR, REPLY_RC
# Arguments: $@ = the command
#######################################
local_read() {
  local out_file err_file rc=0
  out_file="$(mktemp)"; err_file="$(mktemp)"
  run_with_timeout "${timeout_s}" "${err_file}" "$@" >"${out_file}" || rc=$?
  REPLY_RC="${rc}"
  REPLY_OUT="$(<"${out_file}")"
  REPLY_ERR="$(<"${err_file}")"
  rm -f "${out_file}" "${err_file}"
}

#######################################
# Turn a run.zsh exit code and its REFUSED line into a cut-off reason, and record it.
# Globals: sets cut_reason, cut_prompt_holds
# Arguments: $1 = exit code; $2 = run.zsh stdout; $3 = run.zsh stderr
# Returns: 0 when the code is a cut-off; 1 when it is not
#######################################
cut_off_from_rc() {
  local rc="${1}" out="${2}" err="${3}" refused tail_line
  refused="$(print -r -- "${out}"$'\n'"${err}" | awk '/^REFUSED:/ { l=$0 } END { print l }')"
  tail_line="$(print -r -- "${out}" | awk '!/^(TYPED|SENT|PANE|BIND|REFUSED|PANES):?/ && !/^\[INFO\]/ && NF { sub(/[[:space:]]+$/, ""); l=$0 } END { print l }')"
  case "${rc}" in
    77) cut_reason='not_opted_in' ;;
    76) cut_reason='other_session' ;;
    75)
      if [[ "${refused}" == *"text"* || "${refused}" == *"holds"* ]]; then
        cut_reason='holds_text'; cut_prompt_holds="${tail_line}"
      else
        cut_reason='busy'; cut_prompt_holds="${refused#REFUSED: }"
      fi ;;
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
# Returns: 0 when exactly one pane matches; 1 when cut off (no_pane, ambiguous_pane, host_unreachable)
#######################################
find_pane() {
  drive --list
  if (( REPLY_RC != 0 )); then
    cut_reason='host_unreachable'; cut_prompt_holds="$(last_line "${REPLY_ERR}"$'\n'"${REPLY_OUT}")"
    pane_label="${target}"
    log::warn "run.zsh --list failed | rc='${REPLY_RC}' detail='${cut_prompt_holds}'"
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
  nickname="$(print -r -- "${lines[1]}" | awk '{ s=index($0, ": "); if (!s) exit; rest=substr($0, s + 2); e=index(rest, " -- "); if (e) rest=substr(rest, 1, e - 1); print rest }')"
  log::info "Pane found | pane='${pane_label}' nickname='${nickname}'"
  return 0
}

#######################################
# Read one command's output on the host through the pane, wrap-proof and rc-carrying. The marker is
# `@<nonce>@`, a fresh nonce per read, built on the host from pieces (so the echoed command never starts
# a line with it) and unknown to earlier reads, so payload still on the screen from a previous read is
# never swept into this one. The host prints <marker>BEGIN, then the command's output plus its exit
# code as a trailing __RC= line, gzipped, base64-encoded, folded, the marker on every line, then
# <marker>END <length>; the length catches a truncated capture. gzip keeps a 40 KB bd list inside one
# pane capture.
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
  drive --target "${target}" --no-run-log --lines "${CAPTURE_LINES}" --timeout "${timeout_s}" --cmd "${cmd_line}"
  local raw="${REPLY_OUT}" rc="${REPLY_RC}"
  if (( rc != 0 )) && cut_off_from_rc "${rc}" "${REPLY_OUT}" "${REPLY_ERR}"; then
    return 2
  fi
  local end_line expected payload
  end_line="$(print -r -- "${raw}" | awk -v m="${marker}" 'index($0, m "END ") == 1 && $2 ~ /^[0-9]+$/ { l=$0 } END { print l }')"
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
  REPLY_OUT="$(print -r -- "${decoded}" | awk '/^__RC=[0-9]+$/ { exit } { print }')"
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
# A bd JSON list trimmed to the fields a briefing uses; [] for empty output; an error object when the
# command failed or did not print an array.
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
#######################################
# The JSON part of a command's output: bd can print a notice line before its --json body (and the
# host merges stderr), so everything before the first line opening a value is dropped.
# Arguments: $1 = raw output
#######################################
json_part() { print -r -- "${1}" | awk 'f || /^[[:space:]]*[\[{]/ { f=1; print }'; }

bead_list() {
  local raw="${1}" rc="${2}" why="${3}" trimmed
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  if [[ -z "${raw//[[:space:]]/}" ]]; then print -r -- '[]'; return 0; fi
  if trimmed="$(json_part "${raw}" | jq -ce 'if type == "array" then [.[] | {id, title, priority, type: (.issue_type // .type // null), parent: (.parent // null), assignee: (.assignee // null), updated_at: (.updated_at // null)}] else error("not an array") end' 2>/dev/null)"; then
    print -r -- "${trimmed}"
    return 0
  fi
  json_error "not a JSON array: $(print -r -- "${raw}" | head -c 160 | tr '\n' ' ')"
}

#######################################
# Lines of text as {text, ids}: ids are the bead ids found at line starts.
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
text_section() {
  local raw="${1}" rc="${2}" why="${3}"
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  jq -cn --arg t "${raw}" '{text: $t, ids: ([$t | split("\n")[] | capture("^\\s*(?<id>[a-z]+-[a-z0-9]{2,}(\\.[0-9]+)?)\\b")? | .id] | unique)}'
}

#######################################
# {text, ids, blockers}: blockers maps a blocking bead id to how many beads wait on it, from the
# "blocked by: <id>" lines bd blocked prints.
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
blocked_section() {
  local raw="${1}" rc="${2}" why="${3}" base blockers
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  base="$(text_section "${raw}" 0 '')"
  blockers="$(print -r -- "${raw}" \
    | awk 'tolower($0) ~ /blocked by/ { s=$0; sub(/.*[Bb]locked by[^:\[]*[:\[][[:space:]]*/, "", s); gsub(/[\]\[]/, "", s); n=split(s, ids, /[,[:space:]]+/); for (i=1; i<=n; i++) if (ids[i] ~ /^[a-z]+-[a-z0-9.]+$/) c[ids[i]]++ } END { for (k in c) printf "%s\t%d\n", k, c[k] }' \
    | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries')"
  jq -cn --argjson b "${base}" --argjson k "${blockers}" '$b + {blockers: $k}'
}

#######################################
# A git section {dirty: [paths], log: [{hash, subject}]} from status --short and log --oneline.
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
git_section() {
  local raw="${1}" rc="${2}" why="${3}"
  if (( rc != 0 )); then json_error "${why:-"git failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  jq -cn --arg t "${raw}" '($t | split("\n") | map(select(length > 0))) as $l
    | {dirty: [$l[] | select(test("^[ MADRCU?!]{2} "))], log: [$l[] | select(test("^[0-9a-f]{7,} ")) | capture("^(?<hash>[0-9a-f]+) (?<subject>.*)$")]}'
}

#######################################
# {count} from a bd JSON list; 0 for empty output; an error object otherwise.
# Arguments: $1 = raw output; $2 = rc; $3 = why the read failed, if it did
#######################################
count_section() {
  local raw="${1}" rc="${2}" why="${3}" n
  if (( rc != 0 )); then json_error "${why:-"command failed (rc ${rc}): $(last_line "${raw}")"}"; return 0; fi
  if [[ -z "${raw//[[:space:]]/}" ]]; then print -r -- '{"count": 0}'; return 0; fi
  if n="$(json_part "${raw}" | jq -e 'if type == "array" then length else error("not an array") end' 2>/dev/null)"; then
    print -r -- "{\"count\": ${n}}"; return 0
  fi
  json_error "not a JSON array: $(print -r -- "${raw}" | head -c 160 | tr '\n' ' ')"
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
  case "${name}" in
    ready|in_progress) section_json[$name]="$(bead_list "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    human|stale)       section_json[$name]="$(text_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    blocked)           section_json[$name]="$(blocked_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    deferred)          section_json[$name]="$(count_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
    host_git)          section_json[$name]="$(git_section "${REPLY_OUT}" "${REPLY_RC}" "${REPLY_ERR}")" ;;
  esac
  log::info "Read section | section='${name}' rc='${REPLY_RC}'"
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
# Read the host sections in order; stop at the first cut-off and mark the rest unread.
# Globals: section_json, unread, HOST_SECTIONS
#######################################
read_host_sections() {
  local name n rc i=0
  for name in "${HOST_SECTIONS[@]}"; do
    i=$(( i + 1 ))
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

main() {
  local name
  if (( local_mode )); then
    pane_label='local'
    read_host_sections
  elif find_pane; then
    read_host_sections
  else
    unread=("${HOST_SECTIONS[@]}")
    for name in "${HOST_SECTIONS[@]}"; do section_json[$name]='{"unread": true}'; done
  fi
  read_local_sections
  validate_sections

  local cut_off='null'
  if [[ -n "${cut_reason}" ]]; then
    cut_off="$(jq -cn --arg p "${pane_label}" --arg r "${cut_reason}" --arg h "${cut_prompt_holds}" \
      --argjson c "$(json_strings "${candidates[@]}")" --argjson u "$(json_strings "${unread[@]}")" \
      '{pane: $p, reason: $r, prompt_holds: (if $h == "" then null else $h end), candidates: $c, unread: $u}')"
  fi
  local dir json_file json
  dir="$(mk_investigation_dir "${root_dir}" operator-mode)"
  json_file="${dir}/frontier.json"
  json="$(jq -n \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg session "${CLAUDE_CODE_SESSION_ID:-local}" \
    --arg pane "${pane_label}" --arg nick "${nickname}" --arg hd "${host_definition:-local}" \
    --arg beads "${beads_dir}" --arg repo "${repo}" --arg lrepo "${local_repo}" \
    --argjson typed "$(json_strings "${typed[@]}")" --argjson cut "${cut_off}" \
    --argjson ready "${section_json[ready]}" --argjson in_progress "${section_json[in_progress]}" \
    --argjson human "${section_json[human]}" --argjson blocked "${section_json[blocked]}" \
    --argjson stale "${section_json[stale]}" --argjson deferred "${section_json[deferred]}" \
    --argjson host_git "${section_json[host_git]}" --argjson local_git "${section_json[local_git]}" \
    --argjson health "${section_json[health]}" \
    '{captured_at: $ts, session: $session, host_definition: $hd, pane: $pane,
      nickname: (if $nick == "" then null else $nick end), beads_dir: $beads,
      repo: (if $repo == "" then null else $repo end), local_repo: $lrepo, typed: $typed, cut_off: $cut,
      ready: $ready, in_progress: $in_progress, human: $human, blocked: $blocked, stale: $stale,
      deferred: $deferred, host_git: $host_git, local_git: $local_git, health: $health}')"
  print -r -- "${json}" > "${json_file}"
  log::info "Frontier written | json='${json_file}' cut_off='${cut_reason:-none}' typed='${#typed}'"
  cat <<EOF
dir=${dir}
json=${json_file}
cut_off=${cut_reason:-none}
EOF
}

main
