#!/usr/bin/env zsh
# The concert-mcp launcher: find uv, check the checkout, run one subcommand. Callers: bin/cal-add.zsh and bin/cal-del.zsh
# here, and ari-spotify's bin/spotify.zsh (find_uv and require_project only); a change to either function serves all three.
# Sourced after the logging preamble and lib/dry_run.zsh.

readonly CONCERT_MCP_PROJECT="${CONCERT_MCP_HOME:-${HOME}/homelab/apps/concert-mcp}"
readonly -a CONCERT_MCP_UV_FALLBACKS=("/opt/homebrew/bin/uv" "${HOME}/.local/bin/uv")

#######################################
# Find uv: PATH first, then the two install locations a launchd or app PATH may lack.
# Globals: CONCERT_MCP_UV_FALLBACKS
# Arguments: None
# Returns: 1 when no uv is found; prints its path otherwise
#######################################
concert_mcp::find_uv() {
  local candidate
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi
  for candidate in "${CONCERT_MCP_UV_FALLBACKS[@]}"; do
    if [[ -x "${candidate}" ]]; then
      log::info "uv not on PATH; using a fallback | candidate='${candidate}'"
      print -r -- "${candidate}"
      return 0
    fi
  done
  log::err "uv not found | PATH='${PATH}' tried='${(j:, :)CONCERT_MCP_UV_FALLBACKS}' fix='install uv (/ari-dotfiles-nix)'"
  return 1
}

#######################################
# Fail with one [ERROR] line when the concert-mcp checkout is missing.
# Globals: CONCERT_MCP_PROJECT
# Arguments: None
#######################################
concert_mcp::require_project() {
  if [[ -r "${CONCERT_MCP_PROJECT}/pyproject.toml" ]]; then
    return 0
  fi
  log::err "concert-mcp checkout missing | CONCERT_MCP_PROJECT='${CONCERT_MCP_PROJECT}' fix='git -C ~/homelab submodule update --init apps/concert-mcp, or set CONCERT_MCP_HOME'"
  return 1
}

#######################################
# Print the closing dry-run line: the --execute rerun only when concert-mcp would change something.
# Globals: MUT_COUNT
# Arguments: $1 - concert-mcp's exit code; $2 - its reply; $3 - the script path; $4.. - the caller's argv
#######################################
concert_mcp::report() {
  local exit_code="${1}" reply="${2}" script_path="${3}"
  shift 3
  if (( exit_code != 0 )) || [[ "${reply}" == FIX:* ]]; then
    log::info "Dry run stopped before a change; fix the input, no --execute | exit_code='${exit_code}'"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    log::info "The rerun needs the same JSON on stdin again"
  fi
  (( MUT_COUNT += 1 ))
  report_dry_run "${script_path}" "${@}"
}

#######################################
# Run a concert-mcp subcommand that never writes: no --execute gate, the caller's argv after `--` passed as is.
# Globals: CONCERT_MCP_PROJECT
# Arguments: the concert-mcp argv, then `--`, then the caller's argv
#######################################
concert_mcp::exec_read() {
  local -a argv=("${(@)@:#--}")
  local uv
  uv="$(concert_mcp::find_uv)"
  concert_mcp::require_project
  export CONCERT_MCP_OPERATOR_NAME="${CONCERT_MCP_OPERATOR_NAME:-Ari}"
  exec "${uv}" run --project "${CONCERT_MCP_PROJECT}" concert-mcp "${argv[@]}"
}

#######################################
# Parse --execute/--dry-run off the caller's argv and run one concert-mcp subcommand, with concert-mcp's own
# --dry-run standing in for the write unless --execute is on the command line. stdin passes through.
# A leading --read (a subcommand that never writes) skips the gate and runs it as is.
# Globals: CONCERT_MCP_PROJECT, DRY_RUN (via resolve_dry_run)
# Arguments: $1 - the script path, for the rerun line; $2.. - the concert-mcp argv before the caller's flags
#            (e.g. `add --concert`, or `--read healthcheck`), then `--`, then the caller's argv
# Returns: concert-mcp's exit code
#######################################
concert_mcp::run() {
  local script_path="${1}"
  shift
  if [[ "${1:-}" == "--read" ]]; then
    shift
    concert_mcp::exec_read "${@}"
  fi
  local -a fixed=() passthrough=() original=()
  while (( $# > 0 )) && [[ "${1}" != "--" ]]; do
    fixed+=("${1}")
    shift
  done
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  original=("${@}")
  local execute=false dry_run=false
  while (( $# > 0 )); do
    case "${1}" in
      --execute) execute=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      *) passthrough+=("${1}"); shift ;;
    esac
  done
  resolve_dry_run "${execute}" "${dry_run}"

  local uv
  uv="$(concert_mcp::find_uv)"
  concert_mcp::require_project
  export CONCERT_MCP_OPERATOR_NAME="${CONCERT_MCP_OPERATOR_NAME:-Ari}"
  if ! is_dry_run; then
    exec "${uv}" run --project "${CONCERT_MCP_PROJECT}" concert-mcp "${fixed[@]}" "${passthrough[@]}"
  fi
  local reply exit_code=0
  reply="$("${uv}" run --project "${CONCERT_MCP_PROJECT}" concert-mcp "${fixed[@]}" --dry-run "${passthrough[@]}")" || exit_code=$?
  print -r -- "${reply}"
  concert_mcp::report "${exit_code}" "${reply}" "${script_path}" "${original[@]}"
  return "${exit_code}"
}
