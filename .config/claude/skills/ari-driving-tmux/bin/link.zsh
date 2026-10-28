#!/usr/bin/env zsh
# Print a Markdown link that focuses a tmux pane on click and, with --cmd, types that command into it
# (no Enter), followed by the command in a code block, both inside one blockquote so they read as a unit.
# With --run, the click runs it through run_log in that pane and switches back to the clicked pane; an
# interactive run (--interactive, or auto-detected: sudo, ssh, tsh, logins) keeps Ari in that pane until the
# command finishes, since it will ask him something there, and run_log switches him back then.
# Clicking runs focus.zsh through the tmux-pane:// branch of ~/.config/tmux/plugin/osc8-hyperlinks.conf.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --help

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

readonly SCHEME='tmux-pane://'
readonly PATH_PREFIX=/opt/homebrew/bin
# Commands that ask something in the pane (a password, a 2FA tap, a [y/N], a login), by first word, or by
# first two words; a --run of one is interactive unless --no-interactive says otherwise.
readonly -a INTERACTIVE_COMMANDS=(sudo su ssh tsh passwd login kinit doas)
readonly -a INTERACTIVE_COMMAND_PAIRS=('gh auth' 'aws sso' 'gws auth' 'op signin' 'vault login' 'git push')
# Skipped before the first word: leading VAR=value assignments and these wrappers (with their flags).
readonly -a COMMAND_WRAPPERS=(run_log env time)

# --- Help ---

help() {
  cat <<EOF
${c_green}link.zsh${c_rst} — print a click-to-focus, click-to-type or click-to-run link for a tmux pane

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --pane 2.4|%N [--cmd TEXT | --run TEXT [--interactive | --no-interactive]]

${c_bold}Options:${c_rst}
  --pane 2.4|%N window.pane as Ari reads it off prefix-q (exact match in his most recently active
                session), or a tmux pane ID (a bare number is taken as %N)
  --cmd TEXT    command the click types into the pane, without Enter
  --run TEXT    command the click runs there through run_log; the click switches back to the pane the
                link was clicked in, and run_log types 'run_log artifact: <dir>' into its prompt
  --interactive with --run: TEXT will ask something in the pane (a password, a 2FA tap, a [y/N], a login),
                so the click stays there and run_log switches back when TEXT finishes. Assumed, with a
                note on stderr, when TEXT starts with ${(j:, :)INTERACTIVE_COMMANDS}, or
                ${(j:, :)INTERACTIVE_COMMAND_PAIRS} (after any VAR=value and ${(j:/:)COMMAND_WRAPPERS})
  --no-interactive
                with --run: a plain run even when TEXT looks interactive
  -h, --help    show this help

TEXT is one line: a newline, Tab or other control character, or a leading clear, is refused.

${c_bold}Output:${c_rst}
  Focus only:
    [ID=%301|pane=2.5](tmux-pane://301)
  Focus, then type (paste as-is into chat):
    > [ID=%301|pane=2.5](tmux-pane://301?cmd=kubectl%20get%20pods)
    > \`\`\`zsh
    > kubectl get pods
    > \`\`\`
  Run and return (paste as-is into chat):
    > [▶ run in ID=%301|pane=2.5](tmux-pane://301?run=kubectl%20get%20pods)
    > \`\`\`zsh
    > kubectl get pods
    > \`\`\`
  Interactive run (paste as-is into chat):
    > [▶ run (interactive: stays there until it finishes) in ID=%301|pane=2.5](tmux-pane://301?run=sudo%20ls&interactive=1)
    > \`\`\`zsh
    > sudo ls
    > \`\`\`
EOF
}

# --- Actions ---

#######################################
# Resolve --pane to a pane ID, exactly: tmux's own target lookup is fuzzy.
# Arguments: $1 pane as given (2.4, %N or N)
# Outputs: the pane ID on stdout
# Returns: 1 with an error logged when nothing matches
#######################################
resolve_pane() {
  local given="${1}" pane_id="" exit_code=0
  if [[ "${given}" == <0-> ]]; then
    given="%${given}"
  fi
  pane_id="$(tmux_resolve_pane "${given}")" || exit_code=$?
  if (( exit_code == 2 )); then
    log::err "No attached tmux client to resolve window.pane against | pane='${given}' hint='pass the %N from prefix-q'"
    return 1
  fi
  if (( exit_code != 0 )); then
    log::err "No such pane | pane='${given}' expected='a window.pane in the active session, or a live %N'"
    return 1
  fi
  print -r -- "${pane_id}"
}

#######################################
# Warn when a click would not type: the pane is not opted in, or Claude is not in tmux to be
# returned to. Its prompt may change before the click, so this only warns; focus.zsh decides.
# Globals: TMUX_PANE ARI_DRIVING_OPTION
# Arguments: $1 pane_id  $2 label  $3 mode
#######################################
warn_if_untypeable() {
  local pane_id="${1}" label="${2}" mode="${3}"
  if [[ "$(tmux show-options -pqv -t "${pane_id}" "${ARI_DRIVING_OPTION}")" != "on" ]]; then
    log::warn "Pane not opted in; the click will only focus it | pane='${label}' hint='Ari runs ari-driving on there'"
  fi
  if [[ "${mode}" == run && -z "${TMUX_PANE:-}" ]]; then
    log::warn "Claude is not in a tmux pane; the artifact line has nowhere to return | TMUX_PANE='' hint='hand a fenced run_log step instead'"
  fi
}

#######################################
# The command's first words with leading VAR=value assignments and wrappers (run_log, env, time, and their
# flags) skipped: the program that will run.
# Globals: COMMAND_WRAPPERS
# Arguments: $1 command text
# Outputs: the remaining words, one per line
#######################################
program_words() {
  setopt local_options extended_glob
  local -a words=("${(z)1}")
  local in_wrapper=false
  while (( ${#words} > 0 )); do
    if [[ "${words[1]}" == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      shift words
    elif (( ${COMMAND_WRAPPERS[(Ie)${words[1]}]} )); then
      in_wrapper=true
      shift words
    elif [[ "${in_wrapper}" == "true" && "${words[1]}" == -* ]]; then
      shift words
    else
      break
    fi
  done
  print -rl -- "${words[@]}"
}

#######################################
# Whether a command will ask something in the pane, by its program's name (basename) or its first two words.
# Globals: INTERACTIVE_COMMANDS INTERACTIVE_COMMAND_PAIRS
# Arguments: $1 command text
# Outputs: the matched word or pair on stdout
# Returns: 1 when it looks like a plain command
#######################################
interactive_match() {
  local -a words=("${(@f)$(program_words "${1}")}")
  local first="${${words[1]:-}:t}" pair="${${words[1]:-}:t} ${words[2]:-}"
  if (( ${INTERACTIVE_COMMANDS[(Ie)${first}]} )); then
    print -r -- "${first}"
    return 0
  fi
  if (( ${INTERACTIVE_COMMAND_PAIRS[(Ie)${pair}]} )); then
    print -r -- "${pair}"
    return 0
  fi
  return 1
}

#######################################
# Decide whether a --run link is interactive: the flag given, else auto-detected with one note on stderr.
# Arguments: $1 flag (interactive|no-interactive|'')  $2 command text
# Outputs: true or false on stdout
#######################################
choose_interactive() {
  local flag="${1}" cmd="${2}" matched
  if [[ "${flag}" == "interactive" ]]; then
    print -r -- true
    return
  fi
  if [[ "${flag}" == "no-interactive" ]]; then
    print -r -- false
    return
  fi
  if matched="$(interactive_match "${cmd}")"; then
    log::info "Interactive run: the command will ask something in the pane, so the click stays there until it finishes | matched='${matched}' hint='--no-interactive for a plain run'"
    print -r -- true
    return
  fi
  print -r -- false
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
  setopt local_options extended_glob
  # === PARSE ===
  local pane="" cmd="" mode="" interactive_flag=""
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --pane)     pane="${2:?--pane requires a value}"; shift 2 ;;
    --cmd|--run)
      if [[ -n "${mode}" ]]; then
        log::err "Pick one of --cmd and --run | given='--${mode} ${1}'"
        return 1
      fi
      mode="${1#--}"; cmd="${2:?${1} requires a value}"; shift 2 ;;
    --interactive|--no-interactive)
      interactive_flag="${1#--}"; shift ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  export PATH="${PATH_PREFIX}:${PATH}"

  # === VALIDATE ===
  local refusal
  if [[ -n "${mode}" ]] && ! refusal="$(tmux_text_refusal "${cmd}")"; then
    log::err "Refusing the command | reason='${refusal}'"
    return 1
  fi
  if [[ -n "${interactive_flag}" && "${mode}" != run ]]; then
    log::err "--${interactive_flag} needs --run | mode='${mode:-none}'"
    return 1
  fi
  if [[ "${pane}" != (<0->.<0->|%<0->|<0->) ]]; then
    log::err "Missing or malformed --pane | pane='${pane}' expected='2.4, %N or N'"
    help
    return 1
  fi
  if ! tmux list-sessions >/dev/null 2>&1; then
    log::err "No tmux server | hint='hand a fenced block instead'"
    return 1
  fi
  local pane_id label
  pane_id="$(resolve_pane "${pane}")" || return 1
  label="$(tmux display-message -p -t "${pane_id}" "${ARI_DRIVING_LABEL_FORMAT}")"

  # === LOGIC ===
  if [[ -n "${mode}" ]]; then
    warn_if_untypeable "${pane_id}" "${label}" "${mode}"
  fi
  local url="${SCHEME}${pane_id#%}"
  if [[ -z "${cmd}" ]]; then
    print -r -- "[${label}](${url})"
    return 0
  fi
  url+="?${mode}=$(percent_encode "${cmd}")"
  local text="${label}" interactive=false
  if [[ "${mode}" == run ]]; then
    interactive="$(choose_interactive "${interactive_flag}" "${cmd}")"
    text="▶ run in ${label}"
  fi
  if [[ "${interactive}" == "true" ]]; then
    url+="&interactive=1"
    text="▶ run (interactive: stays there until it finishes) in ${label}"
  fi
  local fence='```'
  if [[ "${cmd}" == *'```'* ]]; then
    fence='````'
  fi
  print -r -- "> [${text}](${url})"
  print -r -- "> ${fence}zsh"
  print -r -- "> ${cmd}"
  print -r -- "> ${fence}"
}

main "${@}"
