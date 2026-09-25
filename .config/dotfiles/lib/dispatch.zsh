# dotfiles/lib/dispatch.zsh — main: flags before the verb, the verb, its arguments; help from the
# verbs themselves.
#
# A verb is a file cmd/<verb>.zsh defining cmd_<verb> (parses its own arguments, zparseopts) and
# help_<verb> (its help; the FIRST line is the one-line synopsis the top-level help lists).
# Adding the file adds the verb: the table is ${(k)functions[(I)cmd_*]}.

# Every verb, sorted.
verbs() { print -rl -- ${(o)${(k)functions[(I)cmd_*]#cmd_}}; }

usage_error() {
  log::err "$*"
  help >&2
  exit 64
}

# The verb's help, or a bare line for one without.
help_verb() {
  local verb="${1}"
  if (( ${+functions[help_${verb}]} )); then "help_${verb}"; else print -r -- "dotfiles ${verb}"; fi
}

# dotfiles --help: the header and one synopsis per verb. --verbose --help: every verb's whole help.
help() {
  [[ -t 1 ]] || log::colors_off
  local verb
  cat <<EOF
${c_green}dotfiles${c_rst} — the two-tier dotfiles, and the machine they describe

${c_bold}Usage:${c_rst} dotfiles [--dry-run] [--verbose] [--timing] [--local] <verb> [args]
       dotfiles <verb> --help        dotfiles --verbose --help (every verb's help)

${c_bold}Verbs:${c_rst}
EOF
  if log::is_debug_on; then
    for verb in "${(@f)$(verbs)}"; do
      print
      help_verb "${verb}"
    done
  else
    for verb in "${(@f)$(verbs)}"; do
      print -r -- "  $(help_verb "${verb}" | head -n 1)"
    done
  fi
  cat <<EOF

${c_bold}Flags before the verb:${c_rst}
  --dry-run    print what would change and change nothing (also accepted after a mutating verb)
  --verbose    log::debug lines; with --help, every verb's help
  --timing     log every timed step's duration (slow ones are logged regardless)
  --local      git and --dir act on the local tier instead of the shared one
  --dir        print the tier's bare repo path and exit

${c_bold}Tiers:${c_rst} shared ${TIER_GIT_DIR[shared]} (work tree ~, git df) · local ${TIER_GIT_DIR[local]} (work tree ~/.local, git ldf)
${c_bold}Steps:${c_rst}  one file each in ${DOTFILES_STEPS}; 'dotfiles steps' lists them, 'dotfiles healthcheck' runs their checks.
${c_bold}Env:${c_rst}    DOTFILES_REMOTE (${DOTFILES_REMOTE}), DOTFILES_GITHUB_LOGIN (${DOTFILES_GITHUB_LOGIN}),
        DOTFILES_SSH_KEY_OP_ITEM/VAULT/PATH (from the local tier), DOTFILES_SLOW_STEP (${DOTFILES_SLOW_STEP}s), NEW_MACHINE_* seams
${c_bold}Exit:${c_rst}   0 ok|warn · 1 fail · 2 error (a check could not run) · 3 preflight · 4 another run holds the lock · 64 usage
EOF
}

main() {
  local verb="" want_help=0
  # === PARSE: flags before the verb ===
  while (( $# > 0 )); do case "${1}" in
    -h|--help)      want_help=1; shift ;;
    --verbose|-v)   export VERBOSE=true; shift ;;
    --dry-run)      export DOTFILES_DRY_RUN=1; shift ;;
    --timing)       TIMING=true; shift ;;
    --local)        GIT_TIER=local; shift ;;
    --dir)          PRINT_DIR=true; shift ;;
    -*)             usage_error "Unknown flag | flag='${1}'" ;;
    *)              verb="${1:l}"; shift; break ;;
  esac; done

  # === LOGIC ===
  if [[ "${PRINT_DIR}" == true ]]; then print -r -- "${TIER_GIT_DIR[${GIT_TIER}]}"; return 0; fi
  if [[ -z "${verb}" ]]; then
    (( want_help )) && { help; return 0; }
    usage_error "Missing verb | valid='${(j:, :)${(f)$(verbs)}}'"
  fi
  (( ${+functions[cmd_${verb}]} )) || usage_error "Unknown verb | verb='${verb}' valid='${(j:, :)${(f)$(verbs)}}'"
  # `dotfiles git …` passes its line to git untouched; every other verb answers --help itself.
  if (( want_help )) || { [[ "${verb}" != git ]] && (( ${@[(I)(-h|--help)]} )); }; then
    help_verb "${verb}"
    return 0
  fi
  "cmd_${verb}" "$@"
}
