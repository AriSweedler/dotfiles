# dotfiles/lib/main.zsh — argument parsing, validation and dispatch to cmd_<command>.

# --- Main ---

main() {
  # === PARSE ===
  local command=""
  local -a only=() skip=() scope_flags=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)      help; return 0 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --timing)       TIMING=true; shift ;;
    --previous)     LOGS_PREVIOUS=true; shift ;;
    --dir)          PRINT_DIR=true; shift ;;
    --repo)         LOGS_REPO="${2:?--repo requires a value}"; shift 2 ;;
    --submodules|--shared|--local)          only+=("${1#--}");    scope_flags+=("${1}"); shift ;;
    --no-submodules|--no-shared|--no-local) skip+=("${1#--no-}"); scope_flags+=("${1}"); shift ;;
    -*)             log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)
      if [[ -n "${command}" ]]; then log::err "Unexpected argument | argument='${1}' command='${command}'"; help; return 1; fi
      command="${1}"; shift
      # git is a passthrough: its own flags must not be parsed here.
      if [[ "${command:l}" == git ]]; then GIT_ARGS=("${@}"); set --; fi ;;
  esac; done

  # === MASSAGE ===
  command="${command:l}"
  # Selecting flags name the scope exactly (none = every part); excluding flags then remove from it.
  (( ${#only} == 0 )) || PUSH_SCOPE=("${(@)PUSH_PARTS:*only}")
  PUSH_SCOPE=("${(@)PUSH_SCOPE:|skip}")
  (( ${only[(Ie)local]} )) && GIT_TIER=local
  if [[ "${PRINT_DIR}" == true ]]; then print -r -- "${TIER_GIT_DIR[${GIT_TIER}]}"; return 0; fi

  # === VALIDATE ===
  if [[ -z "${command}" ]]; then log::err "Missing command | valid_commands='${(j:, :)VALID_COMMANDS}'"; help; return 1; fi
  if (( ! ${VALID_COMMANDS[(Ie)${command}]} )); then
    log::err "Invalid command | command='${command}' valid_commands='${(j:, :)VALID_COMMANDS}'"; help; return 1
  fi
  if [[ "${command}" == push ]] && (( ${#PUSH_SCOPE} == 0 )); then
    log::err "Empty push scope: every part excluded | flags='${scope_flags[*]}' parts='${(j:, :)PUSH_PARTS}'"; help; return 1
  fi

  # === LOGIC ===
  "cmd_${command}"
}
