#!/usr/bin/env zsh
# Print one click-for-title Markdown link per bead, so a bead id in chat says what it is.
# The link is tmux-tooltip's (Ari's dotfiles, ~/.config/bin/tmux-tooltip): its URL carries the card,
# so a click in tmux needs no bd and works for a workspace on another host. When
# ~/.config/tmux-tooltip/beads.conf has a scotty line for the beads' workspace, the link is that
# Scotty's https page for the bead with the card in its query: a phone opens only https links.
# Every call names the workspace's machine (--here or --host-definition), so a host's bead never
# links to this machine's Scotty. Status and priority colors come from the same file, which Ari
# edits; tmux-tooltip knows no bead meanings.
# Run: zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh --here --bead beads-o27 --title 'Graph view: Open-only toggle' --status open --priority 2

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
# BEAD_LINK_CONFIG lets tests/bead_link.test.zsh point the script at a fixture.
readonly CONFIG="${BEAD_LINK_CONFIG:-${HOME}/.config/tmux-tooltip/beads.conf}"
# /ari-driving-remote's host definitions, one file per name (its § Host definitions).
readonly HOST_DEFINITIONS_DIR="${HOME}/.local/share/ari-driving-remote/hosts"
# The definition /ari-driving-remote seeds for this machine; it links like --here.
readonly LOCAL_DEFINITION="local"
# A bd id: prefix, dash, base36 hash, then any .N child suffixes (beads-o27, beads-xy9.2.1).
readonly ID_PATTERN='[A-Za-z0-9_-]##-[A-Za-z0-9]##(.[0-9]##)#'
readonly HOST_PATTERN='[A-Za-z0-9_.-]##'
# A scotty line's key: the id prefix, plus @DEFINITION for a host's workspace.
readonly WORKSPACE_PATTERN="[A-Za-z0-9_-]##(@${HOST_PATTERN})#"
# A Scotty project page: https, URL-safe characters only (a ')' would end the Markdown link), and
# no query or fragment, since the bead rides `?bead=<id>`.
readonly SCOTTY_URL_PATTERN='https://[A-Za-z0-9._~:/%@!$&*+,;=-]##'
readonly SCOTTY_URL_EXAMPLE='https://scotty.example.com/p/beads'
# bd's built-in statuses; a custom status (bd config status.custom) is refused until added here.
readonly -a STATUSES=(open in_progress blocked deferred closed hooked pinned)
readonly -a PRIORITIES=(0 1 2 3 4)
readonly -a CONFIG_FIELDS=(status priority scotty)

# --- Help ---

help() {
  cat <<EOF
${c_green}bead_link.zsh${c_rst} — print a click-for-title Markdown link per bead

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh --here|--host-definition NAME --bead ID --title TITLE [--status S] [--priority N] [--bead …]

${c_bold}Options:${c_rst}
  --here                   the beads live in a workspace on this machine
  --host-definition NAME   they live in a workspace on a host: NAME is its /ari-driving-remote
                           definition (run.zsh --hosts), never a hostname; '${LOCAL_DEFINITION}' means --here
                           Exactly one of the two, once per call: one call links one workspace.
  --bead ID                start a bead's record: its bd id
  --title TITLE            the bead's title (required per bead)
  --status S               its bd status: ${(j:, :)STATUSES}
  --priority N             its priority, ${PRIORITIES[1]}-${PRIORITIES[-1]} (0 is P0); shown as P<N>
  -h, --help               show this help
  Each --bead starts a new record; --title, --status and --priority apply to the latest one.

${c_bold}Config:${c_rst} ${CONFIG}, one rule per line (# comments; no file, no rules):
  status VALUE COLOR, priority N COLOR    color that row; a value with no line is uncolored
  scotty PREFIX[@DEFINITION] URL          a workspace's Scotty project page, copied from Scotty:
    scotty  beads          ${SCOTTY_URL_EXAMPLE}      (this machine's beads-* workspace)
    scotty  beads@laptop   https://scotty.example.org/p/beads     (the one on host laptop)
  PREFIX is the bead id prefix, so two workspaces with one prefix on one machine share a line.
  URL is https, URL-safe characters, no query or fragment (bead_link appends ?bead=ID). A bad or
  repeated line, or a host line naming a URL this machine's lines use, is skipped with a warning.

${c_bold}Output:${c_rst} one Markdown link per --bead on stdout, in order (<c>: the config's color);
  stderr carries [INFO]/[WARN] diagnostics, never links. With a scotty line for the workspace:
  [beads-o27](${SCOTTY_URL_EXAMPLE}?bead=beads-o27&tmux-tooltip=show&title=beads-o27&text=Graph%20view%3A%20Open-only%20toggle&field=status%3Dopen&color=<c>&field=priority%3DP2&color=<c>)
  Without one (with --host-definition laptop, only a beads@laptop line counts), tmux only:
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
# Store one scotty line in scotty_urls, unless its key or URL is malformed or its key repeats.
# Globals: CONFIG, WORKSPACE_PATTERN, SCOTTY_URL_PATTERN, SCOTTY_URL_EXAMPLE, scotty_urls, scotty_lines
# Arguments: $1 line number, $2 workspace key, $3 URL
# Returns: 0; a skipped line logs a warning naming it
#######################################
add_scotty_line() {
  setopt local_options extended_glob
  local line_no="${1}" workspace="${2}" url="${3}"
  if [[ "${workspace}" != ${~WORKSPACE_PATTERN} ]]; then
    log::warn "Skipping scotty line; want PREFIX or PREFIX@DEFINITION | config='${CONFIG}' line_no='${line_no}' workspace='${workspace}' expected='beads@laptop'"
    return 0
  fi
  if [[ "${url}" != ${~SCOTTY_URL_PATTERN} ]]; then
    log::warn "Skipping scotty line; want an https URL of URL-safe characters with no query | config='${CONFIG}' line_no='${line_no}' url='${url}' expected='${SCOTTY_URL_EXAMPLE}'"
    return 0
  fi
  if [[ -n "${scotty_urls[$workspace]:-}" ]]; then
    log::warn "Skipping repeated scotty line; the first one stands | config='${CONFIG}' line_no='${line_no}' first_line_no='${scotty_lines[$workspace]}' workspace='${workspace}'"
    return 0
  fi
  scotty_urls[$workspace]="${url}"
  scotty_lines[$workspace]="${line_no}"
}

#######################################
# Drop each host line whose URL a line for this machine also names: a host's beads never link
# to this machine's Scotty.
# Globals: CONFIG, scotty_urls, scotty_lines
# Returns: 0; each dropped line logs a warning naming it
#######################################
drop_host_lines_on_local_urls() {
  local workspace other
  for workspace in ${(k)scotty_urls}; do
    [[ "${workspace}" == *@* ]] || continue
    for other in ${(k)scotty_urls}; do
      [[ "${other}" == *@* ]] && continue
      [[ "${scotty_urls[$other]}" == "${scotty_urls[$workspace]}" ]] || continue
      log::warn "Skipping scotty line; a host workspace names this machine's Scotty | config='${CONFIG}' line_no='${scotty_lines[$workspace]}' workspace='${workspace}' local_line_no='${scotty_lines[$other]}'"
      unset "scotty_urls[$workspace]"
      break
    done
  done
}

#######################################
# Load CONFIG into colors[FIELD:VALUE]=COLOR and scotty_urls[WORKSPACE]=URL; a missing file loads nothing.
# Globals: CONFIG, CONFIG_FIELDS, colors, scotty_urls, scotty_lines (associative arrays, written)
# Returns: 0; a malformed line is skipped with a warning naming it
#######################################
load_config() {
  if [[ ! -r "${CONFIG}" ]]; then
    log::info "No config; links are uncolored and open only in tmux | config='${CONFIG}'"
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
      log::warn "Skipping config line; want 'FIELD VALUE COLOR' or 'scotty WORKSPACE URL' | config='${CONFIG}' line_no='${line_no}' line='${line}' fields='${(j:, :)CONFIG_FIELDS}'"
      continue
    fi
    if [[ "${words[1]}" == scotty ]]; then
      add_scotty_line "${line_no}" "${words[2]}" "${words[3]}"
      continue
    fi
    key="${words[1]}:${words[2]}"
    colors[$key]="${words[3]}"
  done < "${CONFIG}"
  drop_host_lines_on_local_urls
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
# Check the machine choice: --here or a well-formed --host-definition, exactly once.
# Globals: HOST_PATTERN, HOST_DEFINITIONS_DIR
# Arguments: $1 how many of --here/--host-definition were given, $2 the definition or ''
# Returns: 1 when none, several, or a malformed name was given; an unknown name only warns
#######################################
validate_machine() {
  setopt local_options extended_glob
  local -i given="${1}"
  local definition="${2}"
  if (( given != 1 )); then
    log::err "Name the workspace's machine once: --here, or --host-definition NAME for a host | given='${given}'"
    return 1
  fi
  if [[ -n "${definition}" && "${definition}" != ${~HOST_PATTERN} ]]; then
    log::err "Not a definition name | host_definition='${definition}' expected='laptop'"
    return 1
  fi
  if [[ -n "${definition}" && ! -e "${HOST_DEFINITIONS_DIR}/${definition}" ]]; then
    log::warn "No such /ari-driving-remote definition; names come from run.zsh --hosts | host_definition='${definition}' dir='${HOST_DEFINITIONS_DIR}'"
  fi
}

#######################################
# Print the host part of a workspace key: '' for this machine, the definition for a host.
# Globals: LOCAL_DEFINITION
# Arguments: $1 the --host-definition value or ''
# Outputs: the host part on stdout
#######################################
host_part() {
  local definition="${1}"
  if [[ -z "${definition}" ]]; then
    log::info "Linking beads of this machine's workspace"
    return 0
  fi
  if [[ "${definition}" == "${LOCAL_DEFINITION}" ]]; then
    log::info "The local definition is this machine; linking as --here | host_definition='${definition}'"
    return 0
  fi
  log::info "Linking beads of a host's workspace | host_definition='${definition}'"
  print -r -- "${definition}"
}

#######################################
# Print the --href value that points a bead's link at its workspace's Scotty, or nothing when
# the config names no Scotty for that workspace (the link then opens only in tmux).
# Globals: scotty_urls
# Arguments: $1 id, $2 host part or ''
# Outputs: the URL on stdout
#######################################
scotty_href() {
  local id="${1}" host="${2}"
  local workspace="${id%-*}${host:+@${host}}"
  if [[ -z "${scotty_urls[$workspace]:-}" ]]; then
    log::info "No scotty line for the workspace; the link opens only in tmux | id='${id}' workspace='${workspace}'"
    return 0
  fi
  log::info "Linking to the workspace's Scotty | id='${id}' workspace='${workspace}' url='${scotty_urls[$workspace]}'"
  print -r -- "${scotty_urls[$workspace]}?bead=${id}"
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

#######################################
# Print one bead's link; when tmux-tooltip refuses the --href form (one older than link --href),
# fall back to the tmux-only link.
# Globals: TMUX_TOOLTIP, CONFIG
# Arguments: $1 id, $2 the --href value or '', then the card arguments
# Outputs: the link on stdout
# Returns: 1 when tmux-tooltip refuses the card itself
#######################################
build_link() {
  local id="${1}" href="${2}"
  shift 2
  if [[ -n "${href}" ]] && zsh "${TMUX_TOOLTIP}" link --label "${id}" --href "${href}" "$@"; then
    return 0
  fi
  if [[ -n "${href}" ]]; then
    log::warn "tmux-tooltip refused --href; is it older than link --href? This link opens only in tmux | id='${id}' href='${href}'"
  fi
  if ! zsh "${TMUX_TOOLTIP}" link --label "${id}" "$@"; then
    log::err "tmux-tooltip link failed; a color in the config may be wrong | id='${id}' config='${CONFIG}'"
    return 1
  fi
}

# --- Main ---

main() {
  # === PARSE ===
  local definition=""
  local -i machines=0
  local -a ids=() titles=() statuses=() priorities=()
  local -i n=0
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help) help; return 0 ;;
      --here) machines+=1; shift ;;
      --host-definition) machines+=1; definition="${2:?--host-definition requires a name}"; shift 2 ;;
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
  validate_machine "${machines}" "${definition}"
  for (( i = 1; i <= n; i++ )); do
    validate_bead "${ids[i]}" "${titles[i]}" "${statuses[i]}" "${priorities[i]}"
  done

  # === LOGIC ===
  typeset -gA colors=() scotty_urls=() scotty_lines=()
  load_config
  local host
  host="$(host_part "${definition}")"
  # Links print only once every bead's link is built, so a failure leaves no partial output.
  local -a card links
  local link href
  for (( i = 1; i <= n; i++ )); do
    href="$(scotty_href "${ids[i]}" "${host}")"
    card=(--title "${ids[i]}" --text "${titles[i]}")
    [[ -n "${statuses[i]}" ]] && card+=("${(@f)$(field_args status "${statuses[i]}" "${statuses[i]}")}")
    [[ -n "${priorities[i]}" ]] && card+=("${(@f)$(field_args priority "${priorities[i]}" "P${priorities[i]}")}")
    link="$(build_link "${ids[i]}" "${href}" "${card[@]}")" || return 1
    links+=("${link}")
  done
  print -rl -- "${links[@]}"
}

main "$@"
