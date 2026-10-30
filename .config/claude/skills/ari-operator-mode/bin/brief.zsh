#!/usr/bin/env zsh
# brief.zsh — the deterministic parts of an operator-mode reply, from a capture's frontier.json: the
# header line every reply opens with, or the cut-off output that is the whole reply when the capture
# was cut off (the P0 paragraph, or one waiting line for a pane busy with this session's own command or
# with Ari's own row). Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly STALE_AFTER_S=86400     # an in-progress bead untouched this long counts as stale in the header
readonly CLOSING_QUESTION='Tell me when it is clear, or name another pane?'
readonly WAIT_REASONS=(own_command row_pending row_running)   # not his to clear: one waiting line, never the P0 paragraph

help() {
  cat <<HELP
${c_green}brief.zsh${c_rst} — render the fixed parts of an operator-mode reply from a capture

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir DIR --header [--phase TEXT]
  zsh \$HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir DIR --cut-off

${c_bold}Options:${c_rst}
  --dir DIR      the capture folder frontier.zsh printed as dir= (holds frontier.json)
  --json FILE    the frontier.json itself, in place of --dir
  --header       print the one line every reply in the mode opens with
  --phase TEXT   appended to the header after the capture time, e.g. 'after row 1' (default: fresh read)
  --cut-off      print the cut-off output and exit 3 when the capture was cut off, nothing and exit 0 otherwise:
                 the P0 paragraph, or for own_command, row_pending and row_running one waiting line with its question
  -h, --help     this help

${c_bold}Exit codes:${c_rst} 0 printed (or nothing to print); 3 the cut-off output was printed; 1 a bad call or a file that
  is not a capture (it must hold cut_off and ready).
HELP
}

# --- Parse ---

json_file='' dir='' mode='' phase='fresh read'
while (( $# > 0 )); do
  case "${1}" in
    --dir) dir="${2:?--dir requires a value}"; shift 2 ;;
    --json) json_file="${2:?--json requires a value}"; shift 2 ;;
    --header) mode='header'; shift ;;
    --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
    --cut-off) mode='cut_off'; shift ;;
    -h|--help) help; exit 0 ;;
    *) log::err "Unknown flag | flag='${1}'"; help; exit 1 ;;
  esac
done

# --- Validate ---

if ! command -v jq >/dev/null 2>&1; then log::err "Missing required command | missing='jq'"; exit 1; fi
if [[ -n "${dir}" && -z "${json_file}" ]]; then json_file="${dir}/frontier.json"; fi
if [[ -z "${json_file}" || ! -r "${json_file}" ]]; then log::err "A readable capture is required | json_file='${json_file}' hint='--dir DIR or --json FILE'"; exit 1; fi
if [[ -z "${mode}" ]]; then log::err "One of --header or --cut-off is required"; help; exit 1; fi
if ! jq -e 'type == "object" and has("cut_off") and has("ready")' "${json_file}" >/dev/null 2>&1; then
  log::err "Not a capture: it must be a JSON object with cut_off and ready | json_file='${json_file}'"
  exit 1
fi

# --- Logic ---

#######################################
# The sentence for a cut-off reason, and the move that clears it.
# Arguments: $1 = reason; $2 = prompt_holds; $3 = candidates, comma-joined
#######################################
reason_sentence() {
  local reason="${1}" holds="${2}" cands="${3}"
  case "${reason}" in
    not_opted_in)    print -r -- "is not opted in to driving; run \`ari-driving on\` there" ;;
    other_session)   print -r -- "is bound to another Claude session; run \`ari-driving off\` then \`ari-driving on\` there, or name another pane" ;;
    busy)            print -r -- "is not at a shell prompt (${holds:-something is running}); wait for it, or name another pane" ;;
    holds_text)      print -r -- "holds un-entered text on its prompt; clear it or run it, then tell me" ;;
    no_pane)         print -r -- "does not exist on the host; the panes there are ${cands:-none}; name one by its ID=%N" ;;
    ambiguous_pane)  print -r -- "matches more than one pane (${cands}); name one by its ID=%N" ;;
    read_timed_out)  print -r -- "still has a read of mine running; wait for its prompt to return, then tell me (I never resend)" ;;
    host_unreachable) print -r -- "could not be reached (${holds:-ssh failed}); open \`ssh\` to the host once in a pane, then tell me" ;;
    refused_text)    print -r -- "refused the command text before typing (${holds:-see the error}); this is a bug in the reader, not yours to clear" ;;
    *)               print -r -- "could not be read (${reason}); tell me when it can be" ;;
  esac
}

#######################################
# The one line a waiting capture renders: the pane, what holds it, whose it is, and the one question.
# Arguments: $1 = reason; $2 = pane; $3 = prompt_holds
#######################################
waiting_line() {
  local reason="${1}" pane="${2}" holds="${3}"
  case "${reason}" in
    own_command) print -r -- "Waiting on \`${pane}\`, busy with \`${holds:-a command of mine}\`; nothing of yours to clear. Read again?" ;;
    row_running) print -r -- "Your row is running in \`${pane}\` (\`${holds}\`); tell me what it printed when it ends?" ;;
    row_pending) print -r -- "Your row is on your prompt in \`${pane}\`, not entered: press Enter there, or clear it, then tell me?" ;;
  esac
}

print_header() {
  local reason
  reason="$(jq -r '.cut_off.reason // ""' "${json_file}")"
  if (( ${WAIT_REASONS[(Ie)${reason}]} )); then   # the waiting line replaces the header too: one renderer
    waiting_line "${reason}" "$(jq -r '.cut_off.pane' "${json_file}")" "$(jq -r '.cut_off.prompt_holds // ""' "${json_file}")"
    return 0
  fi
  jq -r --arg phase "${phase}" --argjson stale_after "${STALE_AFTER_S}" '
    (.captured_at | if . == null then 0 else fromdateiso8601 end) as $now |
    def n(v): if (v | type) == "array" then (v | length | tostring)
              elif (v | type) == "object" and (v | has("error")) then "failed" else "?" end;
    def ids(v): if (v | type) == "object" and (v | has("ids")) then (v.ids | length | tostring)
                elif (v | type) == "object" and (v | has("error")) then "failed" else "?" end;
    def stale_count: if (.in_progress | type) == "array" and (.captured_at != null) then
        ([.in_progress[] | select(.updated_at != null) | select((( $now - (.updated_at | fromdateiso8601)) > $stale_after))] | length | tostring)
      else "?" end;
    def git_line: [
        (if (.host_git | type) == "object" and (.host_git | has("log")) then {label: .host_definition, g: .host_git} else empty end),
        (if (.local_git | type) == "object" and (.local_git | has("log")) then {label: "this Mac", g: .local_git} else empty end)
      ] | if length == 0 then "checkout unread"
          else .[0] | .label + " " + ((.g.log[0].hash) // "no commits") + " " + (if (.g.dirty | length) == 0 then "clean" else "dirty " + (.g.dirty | length | tostring) end) end;
    (.captured_at // "" | if . == "" then "" else sub("^[0-9-]+T"; "") | sub(":[0-9]{2}Z$"; "Z") end) as $at |
    (if (.waited_s // 0) > 0 then "; waited " + (.waited_s | tostring) + "s for " + .pane else "" end) as $waited |
    if .cut_off != null then "Cut off: " + .cut_off.pane + " (" + .cut_off.reason + "); tracker unread; read " + $at
    else "Ready " + n(.ready) + ", in progress " + n(.in_progress) + ", human " + ids(.human) + ", blocked " + ids(.blocked)
         + ", stale " + stale_count + "; " + git_line + "; read " + $at + $waited + "; " + $phase end
  ' "${json_file}"
}

print_cut_off() {
  if [[ "$(jq -r '.cut_off == null' "${json_file}")" == 'true' ]]; then
    return 0
  fi
  local pane reason holds cands unread_list sentence holds_sentence=''
  pane="$(jq -r '.cut_off.pane' "${json_file}")"
  reason="$(jq -r '.cut_off.reason' "${json_file}")"
  holds="$(jq -r '.cut_off.prompt_holds // ""' "${json_file}")"
  if (( ${WAIT_REASONS[(Ie)${reason}]} )); then   # a wait, never his P0
    waiting_line "${reason}" "${pane}" "${holds}"
    return 3
  fi
  cands="$(jq -r '(.cut_off.candidates // []) | join(", ")' "${json_file}")"
  unread_list="$(jq -r '(.cut_off.unread // []) | join(", ")' "${json_file}")"
  sentence="$(reason_sentence "${reason}" "${holds}" "${cands}")"
  if [[ "${reason}" == holds_text && -n "${holds}" ]]; then
    holds_sentence=" Its prompt holds, verbatim: \`${holds}\`."
  fi
  print -r -- "**P0, cut off from the tracker.** The pane \`${pane}\` ${sentence}; I read nothing from the tracker or the host checkout this turn.${holds_sentence} Unread: ${unread_list}. This is yours to clear; I do nothing else until it is. ${CLOSING_QUESTION}"
  return 3
}

if [[ "${mode}" == header ]]; then print_header; else print_cut_off; fi
