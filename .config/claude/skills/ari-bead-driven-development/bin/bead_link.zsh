#!/usr/bin/env zsh
# Print one click-for-title Markdown link per bead, so a bead id in chat says what it is.
# The link is tmux-tooltip's (Ari's dotfiles, ~/.config/bin/tmux-tooltip): its URL carries the card,
# so a click in tmux needs no bd and works for a workspace on another host. Status and priority
# rows take their colors from ~/.config/tmux-tooltip/beads.conf, which Ari edits; tmux-tooltip knows
# no bead meanings.
# Run: zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh --bead beads-o27 --title 'Graph view: Open-only toggle' --status open --priority 2

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

readonly TMUX_TOOLTIP="${HOME}/.config/bin/tmux-tooltip"
readonly COLOR_CONFIG="${HOME}/.config/tmux-tooltip/beads.conf"
# A bd id: prefix, dash, base36 hash, then any .N child suffixes (beads-o27, beads-xy9.2.1).
readonly ID_PATTERN='[A-Za-z0-9_-]##-[A-Za-z0-9]##(.[0-9]##)#'
# bd's built-in statuses; a custom status (bd config status.custom) is refused until added here.
readonly -a STATUSES=(open in_progress blocked deferred closed hooked pinned)
readonly -a PRIORITIES=(0 1 2 3 4)
readonly -a CONFIG_FIELDS=(status priority)

# --- Help ---

help() {
  cat <<EOF
${c_green}bead_link.zsh${c_rst} — print a click-for-title Markdown link per bead

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh --bead ID --title TITLE [--status S] [--priority N] [--bead …]

${c_bold}Options:${c_rst}
  --bead ID        start a bead's record: its bd id
  --title TITLE    the bead's title (required per bead)
  --status S       its bd status: ${(j:, :)STATUSES}
  --priority N     its priority, ${PRIORITIES[1]}-${PRIORITIES[-1]} (0 is P0); shown as P<N>
  -h, --help       show this help
  Each --bead starts a new record; --title, --status and --priority apply to the latest one.

${c_bold}Colors:${c_rst} ${COLOR_CONFIG}, one 'FIELD VALUE COLOR' per line
  (FIELD status or priority; # comments). A value with no line, or no file, is uncolored.

${c_bold}Output:${c_rst} one line per --bead, in order, from tmux-tooltip link (<c>: the config's color):
  [beads-o27](tmux-tooltip://show?title=beads-o27&text=Graph%20view%3A%20Open-only%20toggle&field=status%3Dopen&color=<c>&field=priority%3DP2&color=<c>)
EOF
}

#######################################
# Fail when tmux-tooltip, which renders the link and handles its click, is not installed.
# Globals: TMUX_TOOLTIP
# Returns: 1 when it is missing
#######################################
check_prerequisites() {
  if [[ ! -r "${TMUX_TOOLTIP}" ]]; then
    log::err "tmux-tooltip not found; it ships with Ari's dotfiles | path='${TMUX_TOOLTIP}'"
    return 1
  fi
}

#######################################
# Load COLOR_CONFIG into colors[FIELD:VALUE]=COLOR; a missing file loads nothing.
# Globals: COLOR_CONFIG, CONFIG_FIELDS, colors (associative array, written)
# Returns: 0; a malformed line is skipped with a warning naming it
#######################################
load_colors() {
  if [[ ! -r "${COLOR_CONFIG}" ]]; then
    log::info "No color config; links are uncolored | config='${COLOR_CONFIG}'"
    return 0
  fi
  local line key
  local -a words
  local -i line_no=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_no+=1
    line="${line%%\#*}"
    words=(${=line})
    (( ${#words} == 0 )) && continue
    if (( ${#words} != 3 )) || (( ! ${CONFIG_FIELDS[(Ie)${words[1]}]} )); then
      log::warn "Skipping config line; want 'FIELD VALUE COLOR' | config='${COLOR_CONFIG}' line_no='${line_no}' line='${line}' fields='${(j:, :)CONFIG_FIELDS}'"
      continue
    fi
    key="${words[1]}:${words[2]}"
    colors[$key]="${words[3]}"
  done < "${COLOR_CONFIG}"
}

#######################################
# Check one bead record.
# Globals: ID_PATTERN, STATUSES, PRIORITIES
# Arguments: $1 id, $2 title, $3 status or '', $4 priority or ''
# Returns: 1 when a value is malformed
#######################################
validate_bead() {
  setopt local_options extended_glob
  local id="${1}" title="${2}" bead_status="${3}" priority="${4}"
  if [[ "${id}" != ${~ID_PATTERN} ]]; then
    log::err "Not a bd id | id='${id}' expected='beads-o27'"
    return 1
  fi
  if [[ -z "${title//[[:space:]]/}" ]]; then
    log::err "Missing or blank --title | id='${id}' title='${title}'"
    return 1
  fi
  if [[ -n "${bead_status}" ]] && (( ! ${STATUSES[(Ie)${bead_status}]} )); then
    log::err "Unknown status | id='${id}' status='${bead_status}' valid='${(j:, :)STATUSES}'"
    return 1
  fi
  if [[ -n "${priority}" ]] && (( ! ${PRIORITIES[(Ie)${priority}]} )); then
    log::err "Priority not 0-4 | id='${id}' priority='${priority}'"
    return 1
  fi
}

#######################################
# Print a --field row and, when the config colors its value, its --color, one argument per line.
# Globals: colors
# Arguments: $1 config field (status|priority), $2 value as bd gives it, $3 value as shown
# Outputs: the tmux-tooltip arguments on stdout
#######################################
field_args() {
  local field="${1}" value="${2}" shown="${3}"
  local key="${field}:${value}"
  print -r -- "--field"
  print -r -- "${field}=${shown}"
  if [[ -z "${colors[$key]:-}" ]]; then
    return 0
  fi
  print -r -- "--color"
  print -r -- "${colors[$key]}"
}

# --- Main ---

main() {
  # === PARSE ===
  local -a ids=() titles=() statuses=() priorities=()
  local -i n=0
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help) help; return 0 ;;
      --bead)
        n+=1
        ids+=("${2:?--bead requires an id}"); titles+=(""); statuses+=(""); priorities+=("")
        shift 2 ;;
      --title|--status|--priority)
        if (( n == 0 )); then
          log::err "Flag before any --bead | flag='${1}'"
          help >&2
          return 1
        fi
        case "${1}" in
          --title) titles[n]="${2:?--title requires a value}" ;;
          --status) statuses[n]="${2:?--status requires a value}" ;;
          --priority) priorities[n]="${2:?--priority requires a value}" ;;
        esac
        shift 2 ;;
      *) log::err "Unknown argument | arg='${1}'"; help >&2; return 1 ;;
    esac
  done

  # === MASSAGE ===
  local -i i
  for (( i = 1; i <= n; i++ )); do
    statuses[i]="${statuses[i]:l}"
  done

  # === VALIDATE ===
  check_prerequisites
  if (( n == 0 )); then
    log::err "No --bead given"
    help >&2
    return 1
  fi
  for (( i = 1; i <= n; i++ )); do
    validate_bead "${ids[i]}" "${titles[i]}" "${statuses[i]}" "${priorities[i]}"
  done

  # === LOGIC ===
  typeset -gA colors=()
  load_colors
  # Links print only once every bead's link is built, so a failure leaves no partial output.
  local -a card links
  local link
  for (( i = 1; i <= n; i++ )); do
    card=(--label "${ids[i]}" --title "${ids[i]}" --text "${titles[i]}")
    [[ -n "${statuses[i]}" ]] && card+=("${(@f)$(field_args status "${statuses[i]}" "${statuses[i]}")}")
    [[ -n "${priorities[i]}" ]] && card+=("${(@f)$(field_args priority "${priorities[i]}" "P${priorities[i]}")}")
    if ! link="$(zsh "${TMUX_TOOLTIP}" link "${card[@]}")"; then
      log::err "tmux-tooltip link failed; a color in the config may be wrong | id='${ids[i]}' config='${COLOR_CONFIG}'"
      return 1
    fi
    links+=("${link}")
  done
  print -rl -- "${links[@]}"
}

main "$@"
