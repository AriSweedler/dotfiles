#!/usr/bin/env zsh
# The ari-spotify CLI: a wrapper over concert-mcp (apps/concert-mcp of the homelab checkout). uv lookup and the
# checkout check come from the concert-mcp launcher in ari-gsw-calendar-add/lib/concert_mcp.zsh.
# `teaser` and `setlist-find` are top-level concert-mcp subcommands; everything else sits under `concert-mcp spotify`.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
readonly LIB_CONCERT_MCP="${SKILLS_DIR}/ari-gsw-calendar-add/lib/concert_mcp.zsh"
if [[ ! -r "${LIB_CONCERT_MCP}" ]]; then
  log::err "missing the shared concert-mcp launcher | path='${LIB_CONCERT_MCP}' fix='link ari-gsw-calendar-add (/ari-dotfiles-skill-registry)'"
  exit 1
fi
source "${LIB_CONCERT_MCP}"

readonly SCRIPT_PATH="${0:a}"
readonly -a TOP_LEVEL=(teaser setlist-find)
readonly -a WRITES=(playlist-create playlist-add playlist-unfollow rename teaser)
readonly -a INTERACTIVE=(auth setlist-auth)

help() {
  cat <<EOF
${c_green}spotify.zsh${c_rst} — Ari's Spotify Liked Songs and playlists, through concert-mcp's Spotify client

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh <command> [flags] [--dry-run | --execute]

${c_bold}Reads:${c_rst}  me, liked, playlists, playlist-tracks, search-artist, setlist-find
${c_bold}Writes:${c_rst} playlist-create, playlist-add, playlist-unfollow, rename, teaser
${c_bold}Ari's terminal only:${c_rst} auth, setlist-auth

${c_bold}Options:${c_rst}
  ${c_cyan}--execute${c_rst}   make the write; without it a write runs as concert-mcp's own --dry-run
  ${c_cyan}--dry-run${c_rst}   the default for a write, said explicitly; wins over --execute
  ${c_cyan}-h, --help${c_rst}  show this help; a command's own flags: <command> --help

${c_bold}Output:${c_rst}
  stdout: one JSON object (--json is always passed). Exit 1 with {"ok": false, "fix": …}: the
  input was wrong. Exit 1 with empty stdout: one [ERROR] line on stderr.
  teaser and setlist-find always run with --no-send: nothing goes to Telegram.
EOF
}

#######################################
# The concert-mcp argv before the flags: teaser and setlist-find are top-level, the rest sit under `spotify`.
# Globals: TOP_LEVEL
# Arguments: $1 - the command
#######################################
subcommand_prefix() {
  local cmd="${1}"
  if (( ${TOP_LEVEL[(Ie)${cmd}]} )); then
    print -r -- "${cmd}"
    return
  fi
  print -r -- "spotify ${cmd}"
}

#######################################
# The flags the wrapper always adds: --json everywhere, --no-send for the top-level commands.
# Globals: TOP_LEVEL
# Arguments: $1 - the command
#######################################
fixed_flags() {
  local cmd="${1}"
  if (( ${TOP_LEVEL[(Ie)${cmd}]} )); then
    print -r -- "--json --no-send"
    return
  fi
  print -r -- "--json"
}

main() {
  local -a args=("${@}") passthrough=()
  local execute=false dry_run=false cmd="${1:-}"
  if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
    help
    return 0
  fi
  shift
  while (( $# > 0 )); do
    case "${1}" in
      --execute) execute=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      *) passthrough+=("${1}"); shift ;;
    esac
  done

  local uv
  uv="$(concert_mcp::find_uv)"
  concert_mcp::require_project
  export CONCERT_MCP_OPERATOR_NAME="${CONCERT_MCP_OPERATOR_NAME:-Ari}"
  local -a prefix=(${(s: :)"$(subcommand_prefix "${cmd}")"})
  local -a extra=(${(s: :)"$(fixed_flags "${cmd}")"})

  if (( ${INTERACTIVE[(Ie)${cmd}]} )); then
    resolve_dry_run "${execute}" "${dry_run}"
    if is_dry_run; then
      log::info "would run; it needs Ari's browser or terminal | cmd='${cmd}'"
      (( MUT_COUNT += 1 ))
      report_dry_run "${SCRIPT_PATH}" "${args[@]}"
      print -r -- "{\"ok\": true, \"dry_run\": true, \"command\": \"${cmd}\"}"
      return 0
    fi
    exec "${uv}" run --project "${CONCERT_MCP_PROJECT}" concert-mcp "${prefix[@]}" "${passthrough[@]}"
  fi

  if (( ${WRITES[(Ie)${cmd}]} )); then
    resolve_dry_run "${execute}" "${dry_run}"
    if is_dry_run; then
      extra+=(--dry-run)
    fi
  fi
  exec "${uv}" run --project "${CONCERT_MCP_PROJECT}" concert-mcp "${prefix[@]}" "${extra[@]}" "${passthrough[@]}"
}

main "$@"
