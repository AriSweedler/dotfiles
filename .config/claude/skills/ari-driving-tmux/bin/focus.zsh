#!/usr/bin/env zsh
# Focus a tmux pane by ID: switch the most recently active client to it, then bring Terminal to the front.
# With a command (--cmd, or a tmux-pane://<n>?cmd=<percent-encoded> link), also type it into the pane
# without pressing Enter — only when the pane is opted in and idle at an empty prompt.
# With --run (or ?run=), type `run_log --deliver-to <return pane> '<command>'`, press Enter, and switch
# back to --return-pane (the pane the link was clicked in): one click runs it in a real terminal, and when
# it finishes run_log types its artifact line into the agent's prompt, so Ari never leaves that pane.
# Clicking a tmux-pane://<n>[?cmd=...] link in tmux runs this (via the tmux-pane:// branch of ~/.config/tmux/plugin/osc8-hyperlinks.conf).
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --help

set -euo pipefail

readonly LIB_LOGGING="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly PANE_ID_PATTERN='%<0->'
readonly LABEL_FORMAT='ID=#{pane_id}|pane=#{window_index}.#{pane_index}'
readonly TERMINAL_APP=Terminal
readonly OPTION='@ari_driving'
readonly PROMPT_END='❯'
readonly SHELL_COMMANDS=(zsh bash sh fish)
# Long enough to see the command start in the target pane before switching back.
readonly RUN_GLANCE_SECONDS=0.4
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
${c_green}focus.zsh${c_rst} — focus a tmux pane by ID and bring ${TERMINAL_APP} to the front

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --pane %N [--cmd TEXT] [--no-activate]

${c_bold}Options:${c_rst}
  --pane %N        tmux pane ID; a bare number is taken as %N (tmux-pane://301 links carry no %).
                   A link payload '301?cmd=<percent-encoded>' sets --cmd too.
  --cmd TEXT       after focusing, type TEXT into the pane (no Enter); refused unless the pane
                   is opted in (ari-driving on) and idle at an empty prompt
  --run TEXT       like --cmd, but type run_log 'TEXT' and press Enter, then switch back to
                   --return-pane. A payload '301?run=<percent-encoded>' sets --run.
  --return-pane %N pane to switch back to after --run (the click handler passes the clicked pane)
  --no-activate    switch tmux only; leave the frontmost app alone
  -h, --help       show this help
EOF
}

# --- Actions ---

#######################################
# The most recently active tmux client.
# Returns: its name on stdout; nothing when no client is attached
#######################################
latest_client() {
  # awk reads every line, so no upstream command dies of SIGPIPE under pipefail.
  tmux list-clients -F '#{client_activity} #{client_name}' | sort -rn | awk 'NR == 1 {sub(/^[^ ]* /, ""); print}'
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
# Refuse unless the pane is opted in and sits at an empty prompt, so a click never types onto
# a running program or into a half-typed line. Reports the refusal on the tmux status line.
# Arguments: $1 pane_id  $2 label
# Returns: 1 when refused
#######################################
check_typeable() {
  setopt local_options extended_glob
  local pane_id="${1}" label="${2}" reason=""
  local current last
  current="$(tmux display-message -p -t "${pane_id}" '#{pane_current_command}')"
  last="$(tmux capture-pane -p -t "${pane_id}" | sed -e '/^[[:space:]]*$/d' | tail -n 1)"
  if [[ "$(tmux show-options -pqv -t "${pane_id}" "${OPTION}")" != "on" ]]; then
    reason="not opted in (run ari-driving on there)"
  elif (( ! ${SHELL_COMMANDS[(Ie)${current}]} )); then
    reason="busy running ${current}"
  elif [[ "${last}" != *"${PROMPT_END}"[[:space:]]# ]]; then
    reason="not at an empty prompt"
  fi
  if [[ -n "${reason}" ]]; then
    log::warn "Not typing into pane | pane='${label}' reason='${reason}'"
    tmux display-message -d 4000 "Not typed into ${label}: ${reason}"
    return 1
  fi
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
# types its artifact line into the return pane (the agent's prompt) and notes it on the status line.
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
# Bring the terminal app to the front, unless told not to.
# Arguments: $1 activate(true|false)
#######################################
activate_terminal() {
  local activate="${1}"
  if [[ "${activate}" != "true" ]]; then
    log::info "Leaving the frontmost app alone | activate='${activate}'"
    return 0
  fi
  log::info "Activating the terminal | app='${TERMINAL_APP}'"
  /usr/bin/osascript -e "tell app \"${TERMINAL_APP}\" to activate" >/dev/null
}

# --- Main ---

main() {
  # === PARSE ===
  local pane_id="" activate=true cmd="" run="" return_pane=""
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
    pane_id="${pane_id%%\?*}"
  elif [[ "${pane_id}" == *\?run=* ]]; then
    run="$(percent_decode "${pane_id#*\?run=}")"
    pane_id="${pane_id%%\?*}"
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
  check_prerequisites || return 1
  if ! is_live_pane "${pane_id}"; then
    log::err "No such pane | pane='${pane_id}' hint='the pane closed since the link was printed'"
    return 1
  fi
  local client
  client="$(latest_client)"
  if [[ -z "${client}" ]]; then
    log::err "No attached tmux client to switch | pane='${pane_id}'"
    return 1
  fi

  # === LOGIC ===
  local label
  label="$(tmux display-message -p -t "${pane_id}" "${LABEL_FORMAT}")"
  switch_to_pane "${client}" "${pane_id}"
  log::info "Focused pane | pane='${label}' client='${client}'"
  if [[ -n "${cmd}" ]] && check_typeable "${pane_id}" "${label}"; then
    type_command "${pane_id}" "${label}" "${cmd}"
  fi
  if [[ -n "${run}" ]] && check_typeable "${pane_id}" "${label}"; then
    run_command "${pane_id}" "${label}" "${run}" "${return_pane}"
    if [[ -n "${return_pane}" && "${return_pane}" != "${pane_id}" ]] && is_live_pane "${return_pane}"; then
      sleep "${RUN_GLANCE_SECONDS}"
      switch_to_pane "${client}" "${return_pane}"
      log::info "Switched back | pane='$(tmux display-message -p -t "${return_pane}" "${LABEL_FORMAT}")'"
    fi
  fi
  activate_terminal "${activate}"
}

main "${@}"
