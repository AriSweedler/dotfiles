# dotfiles/cmd/completion.zsh — `dotfiles completion`: the zsh completion for dotfiles, compiled
# from the declarations (lib/verb.zsh, cmd/kinds.zsh, GLOBAL_FLAG_DESC), and their linter
# (lib/spec.zsh), which is the compiler's front end: nothing is emitted while it has a finding.

verb::define completion 'the zsh completion for dotfiles, compiled from the verb declarations; lint checks them'
verb::usage completion 'completion' 'completion lint' 'completion write'
verb::about completion <<'EOF_ABOUT'
Every verb declares its subcommands, its flags (each with the subcommands
that take it and the kind of value it takes) and its positionals; the
kinds are 'dotfiles kinds'. This verb compiles those declarations into
_dotfiles, the function zsh calls on <TAB>: verbs, subcommands, the flags
that go with the words so far, and each value from its kind. Nothing in it
is written by hand, so a new verb, flag or kind completes once it is
declared and 'completion write' has run.

Without a subcommand: print the function. A declaration with a gap (a
value that names no kind, a flag with no --for in a verb with subcommands,
a Usage form with a flag or kind nothing declares, a flag main() parses
and nothing declares) is a finding; with any, nothing is printed, exit 1.
The dotfiles_docs step fails on a finding and on a stale _dotfiles.
EOF_ABOUT
verb::sub completion lint 'the linter alone: one line per finding, exit 1 on any; nothing printed and exit 0 when clean'
verb::sub completion write 'compile, and write the function to zsh/completions/_dotfiles of this checkout (committed; live after dotfiles switch)'
verb::edit completion --none 'it is compiled; edit a declaration (dotfiles help --edit VERB) or the kinds (cmd/kinds.zsh), then completion write'
verb::section completion 'Exit codes' <<'EOF_CODES'
0   printed, written, or lint clean
1   the linter has a finding (each on stderr)
64  usage
EOF_CODES

# completion::findings: print each finding on stderr; 1 when there is one.
completion::findings() {
  local finding
  local -a reply
  spec::lint
  (( ${#reply} )) || return 0
  for finding in "${reply[@]}"; do log::err "${finding}"; done
  log::err "the declarations have findings; nothing compiled | findings='${#reply}'"
  return 1
}

cmd_completion() {
  local -A opts; local -a args
  verb::parse completion "$@"
  (( ${#args} <= 1 )) || usage_error "completion takes one subcommand | args='${args[*]}'"
  local REPLY text
  case "${args[1]:-}" in
    lint) completion::findings ;;
    '')
      completion::findings || return 1
      need_lib "${ARI_DOTFILES_CMD}/completion/emit.zsh" || return 3
      completion::emit ;;
    write)
      completion::findings || return 1
      need_lib "${ARI_DOTFILES_CMD}/completion/emit.zsh" || return 3
      spec::completion_file
      text="$(completion::emit)"
      if [[ -r "${REPLY}" && "$(<"${REPLY}")" == "${text}" ]]; then log::info "no change | file='${REPLY}'"; return 0; fi
      if is_dry_run; then log::info "would write | file='${REPLY}'"; return 0; fi
      mkdir -p "${REPLY:h}"
      print -r -- "${text}" > "${REPLY}"
      log::info "written | file='${REPLY}' next='commit it; live in a new shell after dotfiles switch'" ;;
    *) usage_error "completion: unknown subcommand | sub='${args[1]}' valid='lint, write'" ;;
  esac
}
