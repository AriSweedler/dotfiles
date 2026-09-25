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

# --- Help ---
# Every help_<verb> is one heredoc in one shape, hand-wrapped at 80 columns:
#   line 1        the one-line description (what the verb table shows)
#   Usage         one form per line, the entrypoint grey: ${DF} <verb> [args]
#   a paragraph   what it does
#   Flags         two aligned columns, every flag the verb takes
#   Env           one variable per line, grey, its description indented on the next line
# ${DF} and ${ENV} are the two colour helpers those heredocs use. DF is set by help::colors: the
# log lib (and its c_* variables) is sourced after this file.
typeset -g DF=""
# A variable name, grey, for an Env section.
ENV() { print -rn -- "${c_grey}${1}${c_rst}"; }
# $HOME as ~, for paths in help.
help::tilde() { print -r -- "${1/#${HOME}/~}"; }
# Colours only on a terminal; DF is the grey entrypoint the heredocs print.
help::colors() {
  [[ -t 1 ]] || log::colors_off
  DF="${c_grey}dotfiles${c_rst}"
}

# The verb's help, or a bare line for one without.
help_verb() {
  local verb="${1}"
  help::colors
  if (( ${+functions[help_${verb}]} )); then "help_${verb}"; else print -r -- "dotfiles ${verb}"; fi
}

# dotfiles --help: the verbs, grey, with their descriptions. --verbose --help: every verb's whole help.
help() {
  help::colors
  local verb width=0
  local -a names=("${(@f)$(verbs)}")
  cat <<EOF
${c_green}dotfiles${c_rst} — the two-tier dotfiles, and the machine they describe

${c_bold}Usage${c_rst}
  ${DF} [--dry-run] [--verbose] [--timing] <verb> [args]
  ${DF} <verb> --help
  ${DF} --verbose --help                every verb's help, one after another

EOF
  if log::is_debug_on; then
    for verb in "${names[@]}"; do
      print -r -- "${c_grey}── dotfiles ${verb} ──${c_rst}"
      help_verb "${verb}"
    done
    return 0
  fi
  for verb in "${names[@]}"; do (( ${#verb} > width )) && width=${#verb}; done
  print -r -- "${c_bold}Verbs${c_rst}"
  for verb in "${names[@]}"; do
    printf '  %s%-*s%s  %s\n' "${c_grey}" "${width}" "${verb}" "${c_rst}" "$(help_verb "${verb}" | head -n 1)"
  done
  cat <<EOF

${c_bold}Tiers${c_rst}
  ${c_grey}shared${c_rst}
      $(help::tilde "${TIER_GIT_DIR[shared]}"), work tree ~, every machine (git df)
  ${c_grey}local${c_rst}
      $(help::tilde "${TIER_GIT_DIR[local]}"), work tree ~/.local, this machine (git ldf)

${c_bold}Exit codes${c_rst}
  0   every step ok, warn or skip
  1   a step failed
  2   a check could not run (busy brew, timeout, crash)
  3   preflight: HOME, macOS, jq, the step registry
  4   another run holds the lock
  64  usage
EOF
}

main() {
  local verb="" want_help=0
  # === PARSE: flags before the verb ===
  while (( $# > 0 )); do case "${1}" in
    -h|--help)      want_help=1; shift ;;
    --verbose|-v)   export VERBOSE=true; shift ;;
    --dry-run)      export ARI_DOTFILES_DRY_RUN=1; shift ;;
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
