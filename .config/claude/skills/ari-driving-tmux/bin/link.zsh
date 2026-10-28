#!/usr/bin/env zsh
# Print a Markdown link that focuses a tmux pane on click and, with --cmd, types that command into it
# (no Enter), followed by the command in a code block, both inside one blockquote so they read as a unit.
# With --run, the click runs it through run_log in that pane and switches back to the clicked pane.
# Clicking runs focus.zsh through the tmux-pane:// branch of ~/.config/tmux/plugin/osc8-hyperlinks.conf.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --help

set -euo pipefail

readonly LIB_LOGGING="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly LABEL_FORMAT='ID=#{pane_id}|pane=#{window_index}.#{pane_index}'
readonly SCHEME='tmux-pane://'
readonly OPTION='@ari_driving'
readonly PATH_PREFIX=/opt/homebrew/bin

# --- Help ---

help() {
  cat <<EOF
${c_green}link.zsh${c_rst} — print a click-to-focus (and optionally click-to-type) link for a tmux pane

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --pane 2.4|%N [--cmd TEXT | --run TEXT]

${c_bold}Options:${c_rst}
  --pane 2.4|%N window.pane as Ari reads it off prefix-q (in his most recently active session), or a
                tmux pane ID (a bare number is taken as %N)
  --cmd TEXT    command the click types into the pane, without Enter
  --run TEXT    command the click runs there through run_log (output captured, handoff copied),
                then switches back to the pane the link was clicked in
  -h, --help    show this help

${c_bold}Output:${c_rst}
  Focus only:
    [ID=%301|pane=2.5](tmux-pane://301)
  Focus, then type (paste as-is into chat):
    > [ID=%301|pane=2.5](tmux-pane://301?cmd=kubectl%20get%20pods)
    > \`\`\`zsh
    > kubectl get pods
    > \`\`\`
EOF
}

# --- Actions ---

#######################################
# Resolve Ari's window.pane to a pane ID in his most recently active session.
# Arguments: $1 window.pane
# Outputs: the pane ID on stdout; nothing when no client is attached or no pane matches
#######################################
resolve_friendly() {
  local friendly="${1}" session
  # awk reads every line, so no upstream command dies of SIGPIPE under pipefail.
  session="$(tmux list-clients -F '#{client_activity} #{client_session}' | sort -rn | awk 'NR == 1 {sub(/^[^ ]* /, ""); print}')"
  if [[ -z "${session}" ]]; then
    return 0
  fi
  tmux display-message -p -t "${session}:${friendly}" '#{pane_id}' 2>/dev/null || true
}

#######################################
# Warn when a click would not type: the pane is not opted in, or not a shell. Its prompt may change
# before the click, so this only warns; focus.zsh decides at click time.
# Arguments: $1 pane_id  $2 label
#######################################
warn_if_untypeable() {
  local pane_id="${1}" label="${2}"
  if [[ "$(tmux show-options -pqv -t "${pane_id}" "${OPTION}")" != "on" ]]; then
    log::warn "Pane not opted in; the click will only focus it | pane='${label}' hint='Ari runs ari-driving on there'"
  fi
}

#######################################
# Percent-encode every byte outside the RFC 3986 unreserved set.
# Arguments: $1 text
# Outputs: the encoded text on stdout
#######################################
percent_encode() {
  setopt local_options extended_glob no_multibyte
  local text="${1}" out="" ch i
  for (( i = 1; i <= ${#text}; i++ )); do
    ch="${text[i]}"
    if [[ "${ch}" == [A-Za-z0-9._~-] ]]; then
      out+="${ch}"
    else
      out+="$(printf '%%%02X' "'${ch}")"
    fi
  done
  print -rn -- "${out}"
}

# --- Main ---

main() {
  # === PARSE ===
  local pane_id="" cmd="" mode=""
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --pane)     pane_id="${2:?--pane requires a value}"; shift 2 ;;
    --cmd)      cmd="${2:?--cmd requires a value}"; mode=cmd; shift 2 ;;
    --run)      cmd="${2:?--run requires a value}"; mode=run; shift 2 ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  export PATH="${PATH_PREFIX}:${PATH}"
  if [[ "${pane_id}" == <0->.<0-> ]]; then
    local friendly="${pane_id}"
    pane_id="$(resolve_friendly "${friendly}")"
    if [[ -z "${pane_id}" ]]; then
      log::err "No pane at that window.pane in the active session | pane='${friendly}'"
      return 1
    fi
  elif [[ "${pane_id}" == <0-> ]]; then
    pane_id="%${pane_id}"
  fi

  # === VALIDATE ===
  if [[ "${pane_id}" != %<0-> ]]; then
    log::err "Missing or malformed --pane | pane='${pane_id}' expected='2.4, %N or N'"
    help
    return 1
  fi
  local label
  if ! label="$(tmux display-message -p -t "${pane_id}" "${LABEL_FORMAT}" 2>/dev/null)"; then
    log::err "No such pane | pane='${pane_id}'"
    return 1
  fi

  # === LOGIC ===
  if [[ -n "${mode}" ]]; then
    warn_if_untypeable "${pane_id}" "${label}"
  fi
  local url="${SCHEME}${pane_id#%}"
  if [[ -z "${cmd}" ]]; then
    print -r -- "[${label}](${url})"
    return 0
  fi
  url+="?${mode}=$(percent_encode "${cmd}")"
  local text="${label}"
  if [[ "${mode}" == run ]]; then
    text="▶ run in ${label}"
  fi
  local fence='```'
  if [[ "${cmd}" == *'```'* ]]; then
    fence='````'
  fi
  local -a lines=("${(@f)cmd}")
  print -r -- "> [${text}](${url})"
  print -r -- "> ${fence}zsh"
  print -rl -- "${(@)lines/#/> }"
  print -r -- "> ${fence}"
}

main "${@}"
