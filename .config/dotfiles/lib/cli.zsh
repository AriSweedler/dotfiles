# dotfiles/lib/cli.zsh — the cli library (~/.config/zsh/lib/cli: verb, kind, spec, emit) set up
# for dotfiles: its name, where its completion is kept, the header the compiled _dotfiles
# carries, and the one lint rule only dotfiles has (globals: the flags before the verb are the
# ones main() parses). The library sits beside dotfiles/ in .config, in the clone and in the
# dotfiles-cli store copy alike.

# The program the library compiles for: always dotfiles (CLI_NAME, lib/env.zsh, is only the name
# fix hints print, and the environment may change it).
typeset -g CLI_PROG=dotfiles
typeset -g CLI_KINDS_CATALOG=cmd/kinds.zsh
typeset -ga CLI_COMPLETION_HEADER=(
  "# _dotfiles: tab completion for dotfiles. COMPILED by 'dotfiles completion write' from the verb"
  "# declarations (cmd/*.zsh), the kinds (cmd/kinds.zsh) and the flags before the verb"
  "# (lib/dispatch.zsh); never edited. Change a declaration, then write it again; the dotfiles_docs"
  "# step fails while this file is not what the declarations compile to."
)
source "${${(%):-%x}:A:h:h:h}/zsh/lib/cli/cli.zsh"

# spec::completion_file: REPLY = where the compiled _dotfiles is kept, in the editable checkout.
spec::completion_file() { REPLY="${ARI_DOTFILES_SRC_CONFIG}/zsh/completions/_dotfiles"; }

SPEC_RULES+=(globals)
# The flags declared for before the verb are the ones main() parses.
spec::rule::globals() {
  local key word
  local -a reply declared=() parsed
  for key in "${(@k)GLOBAL_FLAG_DESC}"; do
    declared+=(${(s:|:)key})
    [[ -n "${GLOBAL_FLAG_DESC[${key}]}" ]] || findings+=("${key}: no description (GLOBAL_FLAG_DESC, lib/dispatch.zsh)")
  done
  (( ${+functions[help::parser_flags]} )) || need_lib "${ARI_DOTFILES_CMD}/help.zsh" || return 0
  help::parser_flags "${ARI_DOTFILES_LIB}/dispatch.zsh"; parsed=("${reply[@]}")
  for word in "${parsed[@]}"; do
    (( ${declared[(Ie)${word}]} )) || findings+=("${word}: main() parses it and GLOBAL_FLAG_DESC (lib/dispatch.zsh) does not declare it")
  done
  for word in "${declared[@]}"; do
    (( ${parsed[(Ie)${word}]} )) || findings+=("${word}: GLOBAL_FLAG_DESC declares it and main() (lib/dispatch.zsh) does not parse it")
  done
}
