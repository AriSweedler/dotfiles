#!/usr/bin/env zsh
# Focus a tmux pane by ID: switch the most recently active client to it, then bring the terminal to the front.
# With a command (--cmd, or a tmux-pane://<n>?cmd=<percent-encoded> link), also type it into the pane
# without pressing Enter, only when the pane passes the gate (opted in, keys reach the shell, idle prompt).
# With --run (or ?run=), type `run_log --deliver-to <return pane> '<command>'`, press Enter, and switch
# back to --return-pane (the pane the link was clicked in): when the command finishes, run_log pastes its
# artifact line into the agent's prompt, so Ari never leaves that pane.
# A link's ?cmd=/?run= is honoured only when it was clicked in a Claude Code pane: any program can print
# an OSC 8 link, and a click on one elsewhere only focuses.
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
  zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --pane %N[?cmd=…|?run=…] [--cmd TEXT | --run TEXT] [--return-pane %M] [--no-activate]

${c_bold}Options:${c_rst}
  --pane %N        tmux pane ID; a bare number is taken as %N (tmux-pane://301 links carry no %).
                   A link payload '301?cmd=<percent-encoded>' or '301?run=…' sets --cmd or --run,
                   honoured only when --return-pane runs Claude Code.
  --cmd TEXT       after focusing, type TEXT into the pane (no Enter); refused unless the pane
                   is opted in (ari-driving on), not in copy mode or synchronized, and idle at an empty prompt
  --run TEXT       like --cmd, but type run_log --deliver-to <return pane> 'TEXT', press Enter, and switch
                   back to --return-pane
  --return-pane %M the pane the link was clicked in (the click handler passes it)
  --no-activate    switch tmux only; leave the frontmost app alone
  -h, --help       show this help

Refusals and failures go to the tmux status line and to stderr (the click handler logs it to /tmp/ari-driving-focus.log).
EOF
}

# --- Actions ---

#######################################
# Say why a click did less than asked, on the status line and in the log.
# Arguments: $1 message
#######################################
notify_status() {
  local message="${1}"
  log::warn "Status line | message='${message}'"
  tmux display-message -d "${STATUS_MS}" "${message}" 2>/dev/null || true
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
# Switch the client to the pane's session, window and pane.
# Arguments: $1 client  $2 pane_id
#######################################
switch_to_pane() {
  local client="${1}" pane_id="${2}"
  tmux switch-client -c "${client}" -t "${pane_id}" \; select-window -t "${pane_id}" \; select-pane -t "${pane_id}"
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
# Refuse unless the pane passes the gate, so a click never types onto a running program, into copy mode,
# into synchronized panes, or onto a half-typed line. Reports the refusal on the tmux status line.
# Arguments: $1 pane_id  $2 label
# Returns: 1 when refused
#######################################
check_typeable() {
  local pane_id="${1}" label="${2}" reason
  if reason="$(tmux_pane_gate_refusal "${pane_id}" "${PROMPT_END}")"; then
    return 0
  fi
  notify_status "Not typed into ${label}: ${reason}"
  return 1
}

#######################################
# Type a command into the pane literally, without Enter.
# Arguments: $1 pane_id  $2 label  $3 cmd
#######################################
type_command() {
  local pane_id="${1}" label="${2}" cmd="${3}"
  tmux send-keys -t "${pane_id}" -l -- "${cmd}"
  log::info "Typed command into pane; Enter not pressed | pane='${label}' chars='${#cmd}'"
}

#######################################
# Run a command in the pane through run_log, so its output is captured; when it finishes, run_log
# pastes its artifact line into the return pane (the agent's prompt).
# Arguments: $1 pane_id  $2 label  $3 cmd  $4 return_pane (may be empty)
#######################################
run_command() {
  local pane_id="${1}" label="${2}" cmd="${3}" return_pane="${4}"
  local deliver=""
  if [[ -n "${return_pane}" && "${return_pane}" != "${pane_id}" ]]; then
    deliver="--deliver-to ${return_pane} "
  fi
  tmux send-keys -t "${pane_id}" -l -- "run_log ${deliver}${(qq)cmd}"
  tmux send-keys -t "${pane_id}" Enter
  log::info "Started command through run_log | pane='${label}' chars='${#cmd}'"
}

#######################################
# Gate, then type or run, under the pane's lock so a double click cannot type twice.
# Arguments: $1 pane_id  $2 label  $3 cmd  $4 run  $5 return_pane
# Returns: 0 when something was typed
#######################################
gate_and_type() {
  local pane_id="${1}" label="${2}" cmd="${3}" run="${4}" return_pane="${5}" exit_code=0
  if ! tmux_pane_lock "${pane_id}"; then
    notify_status "Not typed into ${label}: another click is typing there"
    return 1
  fi
  if ! check_typeable "${pane_id}" "${label}"; then
    exit_code=1
  elif [[ -n "${cmd}" ]]; then
    type_command "${pane_id}" "${label}" "${cmd}"
  else
    run_command "${pane_id}" "${label}" "${run}" "${return_pane}"
  fi
  sleep "${TYPE_SETTLE_SECONDS}"
  tmux_pane_unlock "${pane_id}"
  return "${exit_code}"
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
  local pane_id="" activate=true cmd="" run="" return_pane="" from_link=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)       help; return 0 ;;
    --pane)          pane_id="${2:?--pane requires a value}"; shift 2 ;;
    --cmd)           cmd="${2:?--cmd requires a value}"; shift 2 ;;
    --run)           run="${2:?--run requires a value}"; shift 2 ;;
    --return-pane)   return_pane="${2:?--return-pane requires a value}"; shift 2 ;;
    --no-activate)   activate=false; shift ;;
    -*)              log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)               log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  export PATH="${PATH_PREFIX}:${PATH}"
  if [[ "${pane_id}" == *\?cmd=* ]]; then
    cmd="$(percent_decode "${pane_id#*\?cmd=}")"
    pane_id="${pane_id%%\?*}" from_link=true
  elif [[ "${pane_id}" == *\?run=* ]]; then
    run="$(percent_decode "${pane_id#*\?run=}")"
    pane_id="${pane_id%%\?*}" from_link=true
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
  local refusal
  if [[ -n "${cmd}${run}" ]] && ! refusal="$(tmux_text_refusal "${cmd}${run}")"; then
    notify_status "Focused only: the link's command ${refusal}"
    cmd="" run=""
  fi
  if [[ "${from_link}" == "true" && -n "${cmd}${run}" ]] && ! is_payload_trusted "${return_pane}"; then
    cmd="" run=""
  fi
  if [[ -n "${run}" && ! -x "${RUN_LOG_BIN}" ]]; then
    notify_status "Focused only: run_log is not installed at ${RUN_LOG_BIN}"
    run=""
  fi

  # === LOGIC ===
  local label
  label="$(tmux display-message -p -t "${pane_id}" "${ARI_DRIVING_LABEL_FORMAT}")"
  switch_to_pane "${client}" "${pane_id}"
  log::info "Focused pane | pane='${label}' client='${client}'"
  if [[ -n "${cmd}${run}" ]] && gate_and_type "${pane_id}" "${label}" "${cmd}" "${run}" "${return_pane}" \
      && [[ -n "${run}" && -n "${return_pane}" && "${return_pane}" != "${pane_id}" ]] && is_live_pane "${return_pane}"; then
    sleep "${RUN_GLANCE_SECONDS}"
    switch_to_pane "${client}" "${return_pane}"
    log::info "Switched back | pane='$(tmux display-message -p -t "${return_pane}" "${ARI_DRIVING_LABEL_FORMAT}")'"
  fi
  activate_terminal "${activate}"
}

main "${@}"
