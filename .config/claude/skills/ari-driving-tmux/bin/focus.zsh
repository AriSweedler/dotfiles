#!/usr/bin/env zsh
# Focus a tmux pane by ID: switch the most recently active client to it, then bring the terminal to the front.
# With a command (--cmd, or a tmux-pane://<n>?cmd=<percent-encoded> link), also type it into the pane
# without pressing Enter, only when the pane passes the gate (opted in, keys reach the shell, idle prompt).
# A long command is typed laid out as the link's code block shows it (lib/wrap.zsh), several lines as one
# bracketed paste. With --run (or ?run=), type `run_log --deliver-to <return pane>` and the command as one
# shell string (quoted, or in a heredoc when laid out or full of quotes), press Enter, and switch
# back to --return-pane (the pane the link was clicked in): when the command finishes, run_log pastes its
# artifact line into the agent's prompt, so Ari never leaves that pane. An interactive run (--interactive,
# or ?run=…&interactive=1: the command will ask something in the pane) adds --focus-after and skips the
# switch back; run_log brings Ari back when the command finishes.
# A link's ?cmd=/?run= is honoured only when it was clicked in a Claude Code pane: any program can print
# an OSC 8 link, and a click on one elsewhere only focuses. A payload refused after the click (gate, lock,
# text, run_log missing) is reported into that Claude Code pane's prompt as ` ari-driving refused: …`.
# Clicking a tmux-pane:// link in tmux runs this (the tmux-pane:// branch of ~/.config/tmux/plugin/osc8-hyperlinks.conf).
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly LIB_TMUX_PANE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
if [[ ! -r "${LIB_TMUX_PANE}" ]]; then
  log::err "Missing tmux pane lib | path='${LIB_TMUX_PANE}'"
  exit 1
fi
source "${LIB_TMUX_PANE}"

readonly LIB_WRAP="${SCRIPT_DIR:h}/lib/wrap.zsh"
if [[ ! -r "${LIB_WRAP}" ]]; then
  log::err "Missing command layout lib | path='${LIB_WRAP}'"
  exit 1
fi
source "${LIB_WRAP}"

# --- Constants ---

readonly PANE_ID_PATTERN='%<0->'
readonly PROMPT_END='❯'
readonly RUN_LOG_BIN="${XDG_CONFIG_HOME:-${HOME}/.config}/bin/run_log"
readonly FOCUS_TERMINAL_PLUGIN="${XDG_CONFIG_HOME:-${HOME}/.config}/zsh/plugins/focus_terminal.zsh"
# With the settle below, long enough to see the command start in the target pane before switching back.
readonly RUN_GLANCE_SECONDS=0.2
# Long enough for the shell to echo typed keys, so a second click waiting on the lock sees them.
readonly TYPE_SETTLE_SECONDS=0.2
readonly STATUS_MS=4000
# A click from tmux runs this without a login shell, so Homebrew's tmux may be off PATH.
readonly PATH_PREFIX=/opt/homebrew/bin

# --- Prerequisites ---

#######################################
# Check that tmux is installed.
# Returns: 1 if it is missing
#######################################
check_prerequisites() {
  if ! command -v tmux >/dev/null 2>&1; then
    log::err "Missing required command | missing='tmux' path='${PATH}'"
    return 1
  fi
}

# --- Help ---

help() {
  cat <<EOF
${c_green}focus.zsh${c_rst} — focus a tmux pane by ID, and type or run a command there

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --pane %N[?cmd=…|?run=…[&interactive=1]] [--cmd TEXT | --run TEXT [--interactive]] [--return-pane %M] [--no-activate]

${c_bold}Options:${c_rst}
  --pane %N        tmux pane ID; a bare number is taken as %N (tmux-pane://301 links carry no %).
                   A link payload '301?cmd=<percent-encoded>' or '301?run=…[&interactive=1]' sets --cmd
                   or --run [--interactive], honoured only when --return-pane runs Claude Code.
  --cmd TEXT       after focusing, type TEXT into the pane (no Enter); refused unless the pane
                   is opted in (ari-driving on), not in copy mode or synchronized, and idle at an empty prompt
  --run TEXT       like --cmd, but type run_log --deliver-to <return pane> with TEXT as one shell string
                   ('TEXT', "TEXT", or a heredoc when it is laid out), press Enter, and switch back to
                   --return-pane
  --interactive    with --run: TEXT will ask something in the pane, so add --focus-after and stay there;
                   run_log switches back to --return-pane when TEXT finishes
  --return-pane %M the pane the link was clicked in (the click handler passes it)
  --no-activate    switch tmux only; leave the frontmost app alone
  -h, --help       show this help

Refusals and failures go to the tmux status line and to stderr (the click handler logs it to /tmp/ari-driving-focus.log).
A refused --cmd/--run is also pasted into --return-pane's prompt, when that pane runs Claude Code, as
' ari-driving refused: <label> <reason>' (bracketed, no Enter), so the agent learns why without a relay.
EOF
}

# --- Actions ---

#######################################
# Say why a click did less than asked, on the status line and in the log. display-message runs its
# text through strftime, which would eat the %N of a pane label, so % is doubled.
# Arguments: $1 message
#######################################
notify_status() {
  local message="${1}"
  log::warn "Status line | message='${message}'"
  tmux display-message -d "${STATUS_MS}" "${message//\%/%%}" 2>/dev/null || true
}

#######################################
# Whether a pane with this ID exists.
# Arguments: $1 pane_id
# Returns: 0 when it exists
#######################################
is_live_pane() {
  local pane_id="${1}"
  local -a pane_ids=("${(@f)$(tmux list-panes -a -F '#{pane_id}')}")
  (( ${pane_ids[(Ie)${pane_id}]} ))
}

#######################################
# Switch the client to the pane's session, window and pane (the lib's tmux_switch_to_pane, which run_log's
# --focus-after also uses).
# Arguments: $1 client  $2 pane_id
#######################################
switch_to_pane() {
  local client="${1}" pane_id="${2}"
  tmux_switch_to_pane "${pane_id}" "${client}"
}

#######################################
# Decode a percent-encoded string (%HH only; '+' stays a plus).
# Arguments: $1 encoded
# Outputs: the decoded text on stdout
#######################################
percent_decode() {
  local encoded="${1}"
  print -rn -- "${(g::)${encoded//\%/\\x}}"
}

#######################################
# Decide whether a link's payload may act: only a click in Claude Code's pane carries one Claude wrote.
# Arguments: $1 return_pane
# Returns: 1 when the payload must be dropped (reason on the status line)
#######################################
is_payload_trusted() {
  local return_pane="${1}"
  if [[ -z "${return_pane}" ]]; then
    notify_status "Focused only: no clicked pane passed, so the link's command was dropped"
    return 1
  fi
  if ! tmux_pane_is_claude "${return_pane}"; then
    notify_status "Focused only: the link was clicked outside a Claude Code pane"
    return 1
  fi
  log::info "Link clicked in a Claude Code pane | return_pane='${return_pane}'"
}

#######################################
# Say why the command was not typed: on the status line, in the log, and, when the link was clicked in a
# Claude Code pane, pasted into that pane's prompt (bracketed, no Enter), so the agent answers the refusal
# instead of waiting for an artifact line that never comes.
# Arguments: $1 label  $2 reason  $3 return_pane (may be empty)
#######################################
report_refusal() {
  local label="${1}" reason="${2}" return_pane="${3}" paste_refusal
  notify_status "Not typed into ${label}: ${reason}"
  if [[ -z "${return_pane}" ]] || ! is_live_pane "${return_pane}" || ! tmux_pane_is_claude "${return_pane}"; then
    log::info "Refusal not reported to a prompt; the clicked pane is not Claude Code | return_pane='${return_pane}'"
    return 0
  fi
  if ! paste_refusal="$(tmux_paste_line "${return_pane}" "ari-driving refused: ${label} ${reason}")"; then
    log::warn "Could not paste the refusal into the Claude Code pane | return_pane='${return_pane}' reason='${paste_refusal}'"
    return 0
  fi
  log::info "Pasted the refusal into the Claude Code pane | return_pane='${return_pane}'"
}

#######################################
# Put text on the pane's command line without running it, as one bracketed paste: zsh's line editor
# inserts it whole, each newline a newline in the buffer, not an Enter. Never send-keys: tmux would read a
# trailing ; of the text as its own command separator.
# Arguments: $1 pane_id  $2 text
# Returns: 1 when the paste failed
#######################################
put_on_line() {
  local pane_id="${1}" text="${2}" buffer="ari-driving-type-$$"
  if ! print -rn -- "${text}" | tmux load-buffer -b "${buffer}" - \
      || ! tmux paste-buffer -p -r -d -b "${buffer}" -t "${pane_id}"; then
    tmux delete-buffer -b "${buffer}" 2>/dev/null || true
    log::err "Could not paste into the pane | pane='${pane_id}' buffer='${buffer}'"
    return 1
  fi
}

#######################################
# Whether a run delivers its artifact line somewhere else: a return pane that exists and is not the target.
# Arguments: $1 pane_id  $2 return_pane (may be empty)
#######################################
delivers_elsewhere() {
  local pane_id="${1}" return_pane="${2}"
  [[ -n "${return_pane}" && "${return_pane}" != "${pane_id}" ]] && is_live_pane "${return_pane}"
}

#######################################
# The text a click puts on the pane's line, laid out as the link's code block shows it: a --cmd as is
# (wrap_command); a --run handed to run_log as one shell string (wrap_run_log_text), with --deliver-to the
# return pane, and --focus-after for an interactive run, since this script will not switch back then.
# Computed before the pane is locked: a long program takes seconds to lay out.
# Arguments: $1 pane_id  $2 cmd  $3 run  $4 return_pane (may be empty)  $5 interactive(true|false)
# Outputs: the text on stdout
#######################################
click_text() {
  local pane_id="${1}" cmd="${2}" run="${3}" return_pane="${4}" interactive="${5}" deliver=""
  if [[ -n "${cmd}" ]]; then
    wrap_command "${cmd}"
    return 0
  fi
  if delivers_elsewhere "${pane_id}" "${return_pane}"; then
    deliver="--deliver-to ${return_pane} "
    if [[ "${interactive}" == "true" ]]; then
      deliver+="--focus-after "
    fi
  fi
  wrap_run_log_text "${deliver}" "${run}"
}

#######################################
# Why laid-out text must not go to this pane: a ` \` continuation and a quoted heredoc are zsh's; another
# shell (fish) would run them differently.
# Arguments: $1 pane_id  $2 text
# Outputs: the reason on stdout
# Returns: 1 when refused
#######################################
layout_refusal() {
  local pane_id="${1}" text="${2}" program
  if [[ "${text}" != *$'\n'* ]]; then
    return 0
  fi
  program="$(tmux display-message -p -t "${pane_id}" '#{pane_current_command}')"
  if [[ "${program}" == (-|)zsh ]]; then
    return 0
  fi
  print -r -- "the command is laid out over several lines, which only zsh reads as one; ${program} runs there"
  return 1
}

#######################################
# Gate, then put the text on the line and, for a run, press Enter, under the pane's lock so a double click
# cannot type twice. A refusal is reported (status line, log, the Claude Code pane's prompt).
# Arguments: $1 pane_id  $2 label  $3 text  $4 enter(true|false)  $5 return_pane
# Returns: 0 when something was typed
#######################################
gate_and_type() {
  local pane_id="${1}" label="${2}" text="${3}" enter="${4}" return_pane="${5}" reason
  if ! tmux_pane_lock "${pane_id}"; then
    report_refusal "${label}" "another click is typing there" "${return_pane}"
    return 1
  fi
  local -i exit_code=0
  if ! reason="$(tmux_pane_gate_refusal "${pane_id}" "${PROMPT_END}")" || ! reason="$(layout_refusal "${pane_id}" "${text}")"; then
    report_refusal "${label}" "${reason}" "${return_pane}"
    exit_code=1
  elif ! put_on_line "${pane_id}" "${text}"; then
    report_refusal "${label}" "the paste into the pane failed" "${return_pane}"
    exit_code=1
  elif [[ "${enter}" == "true" ]]; then
    tmux send-keys -t "${pane_id}" Enter
    log::info "Started command through run_log | pane='${label}' chars='${#text}'"
  else
    log::info "Typed command into pane; Enter not pressed | pane='${label}' chars='${#text}'"
  fi
  sleep "${TYPE_SETTLE_SECONDS}"
  tmux_pane_unlock "${pane_id}"
  return "${exit_code}"
}

#######################################
# After a run started: switch back to the clicked pane, or, for an interactive run, stay and say that
# run_log will switch back when the command finishes.
# Arguments: $1 client  $2 pane_id  $3 label  $4 return_pane  $5 interactive(true|false)
#######################################
return_after_run() {
  local client="${1}" pane_id="${2}" label="${3}" return_pane="${4}" interactive="${5}"
  if ! delivers_elsewhere "${pane_id}" "${return_pane}"; then
    log::info "Staying; the run has no other pane to return to | pane='${label}' return_pane='${return_pane}'"
    return 0
  fi
  if [[ "${interactive}" == "true" ]]; then
    notify_status "✦ Running in ${label}; you return to Claude when it finishes"
    return 0
  fi
  sleep "${RUN_GLANCE_SECONDS}"
  switch_to_pane "${client}" "${return_pane}"
  log::info "Switched back | pane='$(tmux display-message -p -t "${return_pane}" "${ARI_DRIVING_LABEL_FORMAT}")'"
}

#######################################
# Bring the terminal app to the front, unless told not to.
# Arguments: $1 activate(true|false)
#######################################
activate_terminal() {
  local activate="${1}"
  if [[ "${activate}" != "true" ]]; then
    log::info "Leaving the frontmost app alone | activate='${activate}'"
    return 0
  fi
  if [[ ! -r "${FOCUS_TERMINAL_PLUGIN}" ]]; then
    log::warn "No focus_terminal plugin; leaving the frontmost app alone | path='${FOCUS_TERMINAL_PLUGIN}'"
    return 0
  fi
  source "${FOCUS_TERMINAL_PLUGIN}"
  log::info "Activating the terminal | bundle_id='${__CFBundleIdentifier:-}'"
  focus_terminal || true
}

# --- Main ---

main() {
  # === PARSE ===
  local pane_id="" activate=true cmd="" run="" return_pane="" from_link=false interactive=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)       help; return 0 ;;
    --pane)          pane_id="${2:?--pane requires a value}"; shift 2 ;;
    --cmd)           cmd="${2:?--cmd requires a value}"; shift 2 ;;
    --run)           run="${2:?--run requires a value}"; shift 2 ;;
    --interactive)   interactive=true; shift ;;
    --return-pane)   return_pane="${2:?--return-pane requires a value}"; shift 2 ;;
    --no-activate)   activate=false; shift ;;
    -*)              log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)               log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  export PATH="${PATH_PREFIX}:${PATH}"
  # The query is ?cmd=<encoded> or ?run=<encoded>[&interactive=1]; the encoded part holds no '&'.
  local query
  if [[ "${pane_id}" == *\?cmd=* ]]; then
    query="${pane_id#*\?cmd=}"
    cmd="$(percent_decode "${query%%\&*}")"
    pane_id="${pane_id%%\?*}" from_link=true
  elif [[ "${pane_id}" == *\?run=* ]]; then
    query="${pane_id#*\?run=}"
    run="$(percent_decode "${query%%\&*}")"
    pane_id="${pane_id%%\?*}" from_link=true
    if [[ "${query}" == *\&interactive=1(|\&*) ]]; then
      interactive=true
    fi
  fi
  if [[ "${pane_id}" == <0-> ]]; then
    pane_id="%${pane_id}"
  fi

  # === VALIDATE ===
  if [[ "${pane_id}" != ${~PANE_ID_PATTERN} ]]; then
    log::err "Missing or malformed --pane | pane='${pane_id}' expected='%N or N'"
    help
    return 1
  fi
  if [[ -n "${cmd}" && -n "${run}" ]]; then
    log::err "Pick one of --cmd and --run"
    return 1
  fi
  if [[ "${interactive}" == "true" && -z "${run}" ]]; then
    log::err "--interactive needs --run (or a ?run= link)"
    return 1
  fi
  check_prerequisites || return 1
  if ! is_live_pane "${pane_id}"; then
    notify_status "Not focused: no pane ${pane_id} (it closed since the link was printed)"
    return 1
  fi
  local client
  client="$(tmux_latest_client)"
  if [[ -z "${client}" ]]; then
    notify_status "Not focused: no attached tmux client to switch"
    return 1
  fi
  local label
  label="$(tmux display-message -p -t "${pane_id}" "${ARI_DRIVING_LABEL_FORMAT}")"
  if [[ "${from_link}" == "true" && -n "${cmd}${run}" ]] && ! is_payload_trusted "${return_pane}"; then
    cmd="" run=""
  fi
  local refusal
  if [[ -n "${cmd}${run}" ]] && ! refusal="$(tmux_text_refusal "${cmd}${run}")"; then
    report_refusal "${label}" "the link's command ${refusal}" "${return_pane}"
    cmd="" run=""
  fi
  if [[ -n "${cmd}${run}" ]] && ! refusal="$(tmux_opt_in_refusal "${cmd}${run}")"; then
    report_refusal "${label}" "the link's command ${refusal}" "${return_pane}"
    cmd="" run=""
  fi
  if [[ -n "${run}" && ! -x "${RUN_LOG_BIN}" ]]; then
    report_refusal "${label}" "run_log is not installed at ${RUN_LOG_BIN}" "${return_pane}"
    run=""
  fi

  # === LOGIC ===
  local text="" enter=false
  if [[ -n "${cmd}${run}" ]]; then
    text="$(click_text "${pane_id}" "${cmd}" "${run}" "${return_pane}" "${interactive}")"
  fi
  if [[ -n "${run}" ]]; then
    enter=true
  fi
  switch_to_pane "${client}" "${pane_id}"
  log::info "Focused pane | pane='${label}' client='${client}'"
  if [[ -n "${text}" ]] && gate_and_type "${pane_id}" "${label}" "${text}" "${enter}" "${return_pane}" \
      && [[ -n "${run}" ]]; then
    return_after_run "${client}" "${pane_id}" "${label}" "${return_pane}" "${interactive}"
  fi
  activate_terminal "${activate}"
}

main "${@}"
