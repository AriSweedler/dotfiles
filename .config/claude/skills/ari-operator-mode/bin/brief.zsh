#!/usr/bin/env zsh
# brief.zsh — the deterministic parts of an operator-mode reply, from a capture's frontier.json: the
# header line every reply opens with, or the cut-off output that is the whole reply when the capture
# was cut off (the P0 paragraph, or one waiting line for a pane busy with an agent's command or with
# Ari's own row). Run: zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --help

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

readonly WAIT_REASONS=(own_command own_command_persists row_pending row_running)   # not his to clear: one waiting line, never the P0 paragraph
readonly HIS_TO_CLEAR=(not_opted_in other_session busy holds_text no_pane ambiguous_pane)   # the P0 paragraph says so and asks the clear question

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
                 the P0 paragraph, or for own_command, own_command_persists, row_pending and row_running one waiting
                 line with its question
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
    read_timed_out)  print -r -- "still has a read of mine running; I never resend it" ;;
    host_unreachable) print -r -- "could not be reached (${holds:-ssh failed})" ;;
    refused_text)    print -r -- "refused the command text before typing (${holds:-see the error}); a bug in the reader, not yours to clear" ;;
    *)               print -r -- "could not be read (${reason})" ;;
  esac
}

#######################################
# The one question that ends the paragraph, by reason: what clears it, or what Claude does next.
# Arguments: $1 = reason
#######################################
closing_question() {
  case "${1}" in
    read_timed_out)   print -r -- "Tell me when its prompt is back?" ;;
    host_unreachable) print -r -- "Tell me when \`ssh\` to the host works from a pane?" ;;
    refused_text)     print -r -- "Shall I rewrite the read on one line and try once?" ;;
    *)                print -r -- "Tell me when it is clear, or name another pane?" ;;
  esac
}

#######################################
# The one line a waiting capture renders: the pane, what holds it, whose it is, and the one question.
# Arguments: $1 = reason; $2 = pane; $3 = prompt_holds
#######################################
waiting_line() {
  local reason="${1}" pane="${2}" holds="${3}"
  case "${reason}" in
    own_command) print -r -- "Waiting on \`${pane}\`, busy with \`${holds:-a command of mine}\`; an agent's command, nothing of yours to clear. Read again?" ;;
    own_command_persists) print -r -- "Still waiting on \`${pane}\`, busy with \`${holds:-a command of mine}\`; an agent's command, nothing of yours to clear. Wait, or name another pane?" ;;
    row_running) print -r -- "Your row is running in \`${pane}\` (\`${holds}\`); tell me what it printed when it ends?" ;;
    row_pending) print -r -- "Your row is on your prompt in \`${pane}\`, not entered: press Enter there, or clear it, then tell me?" ;;
  esac
}

#######################################
# The cut-off pane's label with its nickname when the capture has one, as every pane is named.
#######################################
cut_pane_label() {
  jq -r '.cut_off.pane + (if .nickname != null then "|nickname=" + .nickname else "" end)' "${json_file}"
}

print_header() {
  local reason
  reason="$(jq -r '.cut_off.reason // ""' "${json_file}")"
  if (( ${WAIT_REASONS[(Ie)${reason}]} )); then   # the waiting line replaces the header too: one renderer
    waiting_line "${reason}" "$(cut_pane_label)" "$(jq -r '.cut_off.prompt_holds // ""' "${json_file}")"
    return 0
  fi
  jq -r --arg phase "${phase}" '
    def n(v): if (v | type) == "array" then (v | length | tostring)
              elif (v | type) == "object" and (v | has("error")) then "failed" else "?" end;
    def ids(v): if (v | type) == "object" and (v | has("ids")) then (v.ids | length | tostring)
                elif (v | type) == "object" and (v | has("error")) then "failed" else "?" end;
    def git_line: [
        (if (.host_git | type) == "object" and (.host_git | has("log")) then {label: .host_definition, g: .host_git} else empty end),
        (if (.local_git | type) == "object" and (.local_git | has("log")) then {label: "this Mac", g: .local_git} else empty end)
      ] | if length == 0 then "checkout unread"
          else .[0] | .label + " " + ((.g.log[0].hash) // "no commits") + " " + (if (.g.dirty | length) == 0 then "clean" else "dirty " + (.g.dirty | length | tostring) end) end;
    (.captured_at // "" | if . == "" then "" else sub("^[0-9-]+T"; "") | sub(":[0-9]{2}Z$"; "Z") end) as $at |
    (if (.waited_s // 0) > 0 then "; waited " + (.waited_s | tostring) + "s for " + .pane else "" end) as $waited |
    if .cut_off != null then "Cut off: " + .cut_off.pane + (if .nickname != null then "|nickname=" + .nickname else "" end) + " (" + .cut_off.reason + "); tracker unread; read " + $at
    else "Ready " + n(.ready) + ", in progress " + n(.in_progress) + ", human " + ids(.human) + ", blocked " + ids(.blocked)
         + ", stale " + ids(.stale) + "; " + git_line + "; read " + $at + $waited + "; " + $phase end
  ' "${json_file}"
}

print_cut_off() {
  if [[ "$(jq -r '.cut_off == null' "${json_file}")" == 'true' ]]; then
    return 0
  fi
  local pane reason holds cands unread_list sentence holds_sentence='' yours=''
  pane="$(cut_pane_label)"
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
  if (( ${HIS_TO_CLEAR[(Ie)${reason}]} )); then yours=' This is yours to clear; I do nothing else until it is.'; else yours=' I do nothing else until it is read.'; fi
  print -r -- "**P0, cut off from the tracker.** The pane \`${pane}\` ${sentence}; I read nothing from the tracker or the host checkout this turn.${holds_sentence} Unread: ${unread_list}.${yours} $(closing_question "${reason}")"
  return 3
}

if [[ "${mode}" == header ]]; then print_header; else print_cut_off; fi
