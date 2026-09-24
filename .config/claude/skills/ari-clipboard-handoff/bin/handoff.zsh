#!/usr/bin/env zsh
# Hand Ari a command or text: render the uniform chat block, or (only when he asked) copy
# text to the clipboard. Recovery of a clobbered clipboard is Raycast's Clipboard History,
# named through the raycast-link widget; this script never reads or restores the clipboard.
# Run: zsh $HOME/.claude/skills/ari-clipboard-handoff/bin/handoff.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Environment variables ---

# The dotfiles widget that names Raycast's Clipboard History with its Karabiner binding.
readonly RAYCAST_LINK="${HANDOFF_RAYCAST_LINK:-${XDG_CONFIG_HOME:-${HOME}/.config}/bin/raycast-link}"

# --- Constants ---

readonly SELF="zsh \$HOME/.claude/skills/ari-clipboard-handoff/bin/handoff.zsh"
readonly VALID_MODES=(print copy)
readonly FENCE='```'
readonly HISTORY_FALLBACK='<Raycast: Clipboard History> raycast://extensions/raycast/clipboard-history/clipboard-history'

# --- Prerequisites ---

#######################################
# Check the binaries a mode needs.
# Arguments:
#   $@ - command names
# Returns: 1 if any are missing
#######################################
check_commands() {
  local missing=()
  for cmd in "${@}"; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# Check if a value is in an array of valid options.
# Arguments:
#   $1 - value to check
#   $2.. - valid options
# Returns: 0 if valid, 1 if not
#######################################
is_valid_option() {
  local val="${1}"; shift
  for opt in "${@}"; do
    [[ "${val}" == "${opt}" ]] && return 0
  done
  return 1
}

########################################################################
# Business logic
########################################################################

#######################################
# Choose the command line the block shows: bare, `! ` (interactive), or run_log (capture).
# Arguments:
#   $1 - command
#   $2 - interactive flag (true/false)
#   $3 - capture flag (true/false)
#   $4 - capture dir ("" for none)
# Returns: the rendered line on stdout
#######################################
render_command_line() {
  local cmd="${1}" interactive="${2}" capture="${3}" capture_dir="${4}"
  if [[ "${interactive}" == "true" ]]; then
    log::info "Rendering interactive form | cmd='${cmd}'"
    echo "! ${cmd}"
    return
  fi
  if [[ "${capture}" == "true" && -n "${capture_dir}" ]]; then
    log::info "Rendering run_log form with dir | cmd='${cmd}' capture_dir='${capture_dir}'"
    echo "run_log --dir ${capture_dir} -- ${cmd}"
    return
  fi
  if [[ "${capture}" == "true" ]]; then
    log::info "Rendering run_log form | cmd='${cmd}'"
    echo "run_log -- ${cmd}"
    return
  fi
  log::info "Rendering bare form | cmd='${cmd}'"
  echo "${cmd}"
}

#######################################
# Print the chat block for one handoff step.
# Arguments:
#   $1 - step number ("" for none)
#   $2 - blocking status ("" for none)
#   $3 - rendered command line
#   $4 - expected outcome
# Returns: markdown on stdout
#######################################
print_block() {
  local step="${1}" blocking="${2}" line="${3}" expect="${4}"
  if [[ -n "${step}" && -n "${blocking}" ]]; then
    echo "${step}. (${blocking})"
  elif [[ -n "${step}" ]]; then
    echo "${step}."
  fi
  echo "${FENCE}zsh"
  echo "${line}"
  echo "${FENCE}"
  echo "Expected: ${expect}"
}

#######################################
# Name Raycast's Clipboard History with its binding, via the dotfiles widget when installed.
# Globals: RAYCAST_LINK, HISTORY_FALLBACK
# Returns: the plain widget line on stdout
#######################################
history_widget() {
  local line
  if [[ -x "${RAYCAST_LINK}" ]] && line="$("${RAYCAST_LINK}" clipboard-history --plain 2>/dev/null)" && [[ -n "${line}" ]]; then
    echo "${line}"
    return
  fi
  log::warn "raycast-link unavailable; naming Clipboard History without its binding | raycast_link='${RAYCAST_LINK}'"
  echo "${HISTORY_FALLBACK}"
}

#######################################
# Mode: copy. Write text to the clipboard. The env marker is what the PreToolUse guard looks
# for in a raw Bash command; it is set here and nowhere else. Raycast keeps the displaced
# clipboard as the second entry of its history.
# Arguments:
#   $1 - text
#######################################
do_copy() {
  local text="${1}"
  print -rn -- "${text}" | HANDOFF_CLIP_OK=1 pbcopy
  log::ok "Copied | chars='${#text}'"
  cat <<EOF
copied_chars=${#text}
previous clipboard: second entry in $(history_widget)
EOF
}

# --- Help ---

help() {
  cat <<EOF
${c_green}handoff${c_rst} — render a command block for Ari, or copy text to his clipboard on request

${c_bold}Usage:${c_rst}
  ${SELF} --print --cmd CMD --expect TEXT [--step N [--blocking | --not-blocking]] [--interactive | --capture [--capture-dir DIR]]
  ${SELF} --copy (--text TEXT | --file PATH)

${c_bold}Modes:${c_rst}
  --print     Print the chat block: fenced command, then "Expected: …". Never touches the clipboard.
  --copy      Copy TEXT to the clipboard. Only when Ari asked. Prints where the displaced clipboard went.

${c_bold}Options:${c_rst}
  --cmd CMD          Command to hand off (--print)
  --expect TEXT      What Ari should see when it worked (--print)
  --step N           Number the block (--print)
  --blocking         Mark the step "(blocks me)" (--print, with --step)
  --not-blocking     Mark the step "(not blocking)" (--print, with --step)
  --interactive      Render as "! CMD" so its output lands in the conversation (--print)
  --capture          Render as "run_log -- CMD" so Claude can read the output back (--print)
  --capture-dir DIR  With --capture: "run_log --dir DIR -- CMD"
  --text TEXT        Text to copy (--copy)
  --file PATH        File whose contents to copy (--copy)
  -h, --help         Show this help

${c_bold}Environment:${c_rst}
  HANDOFF_RAYCAST_LINK  Path of the raycast-link widget (default ${RAYCAST_LINK})

${c_bold}Examples:${c_rst}
  ${SELF} --print --step 1 --blocking --cmd 'gws auth login --scopes …' --expect 'scope_count 16 in gws auth status' --interactive
  ${SELF} --print --cmd 'kubectl get pods -n foo' --expect 'No resources found' --capture --capture-dir /tmp/inv/logs
  ${SELF} --copy --text 'some long command'
EOF
}

# --- Main ---

main() {
  # === PARSE ===
  local mode="" cmd="" expect="" step="" blocking="" text="" file="" capture_dir=""
  local interactive=false capture=false text_set=false

  while (( $# > 0 )); do case "${1}" in
    -h|--help)      help; return 0 ;;
    --print)        mode="print"; shift ;;
    --copy)         mode="copy"; shift ;;
    --cmd)          cmd="${2:?--cmd requires a value}"; shift 2 ;;
    --expect)       expect="${2:?--expect requires a value}"; shift 2 ;;
    --step)         step="${2:?--step requires a value}"; shift 2 ;;
    --blocking)     blocking="blocks me"; shift ;;
    --not-blocking) blocking="not blocking"; shift ;;
    --interactive)  interactive=true; shift ;;
    --capture)      capture=true; shift ;;
    --capture-dir)  capture_dir="${2:?--capture-dir requires a value}"; shift 2 ;;
    --text)         text="${2:?--text requires a value}"; text_set=true; shift 2 ;;
    --file)         file="${2:?--file requires a value}"; shift 2 ;;
    -*)             log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)              log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  if [[ -n "${file}" && "${text_set}" == "false" ]]; then
    if [[ ! -r "${file}" ]]; then
      log::err "Cannot read --file | file='${file}'"
      return 1
    fi
    text="$(cat "${file}")"; text_set=true
  fi

  # === VALIDATE ===
  if [[ -z "${mode}" ]]; then
    log::err "Missing mode | valid_modes='${(j:, :)VALID_MODES}'"; help; return 1
  fi
  if ! is_valid_option "${mode}" "${VALID_MODES[@]}"; then
    log::err "Invalid mode | mode='${mode}' valid_modes='${(j:, :)VALID_MODES}'"; return 1
  fi
  case "${mode}" in
    print)
      [[ -n "${cmd}" ]] || { log::err "Missing --cmd for --print | mode='${mode}'"; help; return 1; }
      [[ -n "${expect}" ]] || { log::err "Missing --expect for --print | mode='${mode}'"; help; return 1; }
      if [[ "${interactive}" == "true" && "${capture}" == "true" ]]; then
        log::err "Pick one of --interactive and --capture | interactive='${interactive}' capture='${capture}'"; return 1
      fi
      if [[ -n "${blocking}" && -z "${step}" ]]; then
        log::err "--blocking/--not-blocking need --step | blocking='${blocking}'"; return 1
      fi ;;
    copy)
      [[ "${text_set}" == "true" ]] || { log::err "Missing --text or --file for --copy | mode='${mode}'"; help; return 1; }
      check_commands pbcopy || return 1 ;;
  esac

  # === LOGIC ===
  case "${mode}" in
    print) print_block "${step}" "${blocking}" "$(render_command_line "${cmd}" "${interactive}" "${capture}" "${capture_dir}")" "${expect}" ;;
    copy)  do_copy "${text}" ;;
  esac
}

main "${@}"
