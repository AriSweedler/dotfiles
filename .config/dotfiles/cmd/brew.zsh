# dotfiles/cmd/brew.zsh — `dotfiles brew`: the declared-state side of Homebrew. The brew model
# (cmd/brew/brew.zsh) and the decree editor (cmd/brew/decree.zsh) are loaded on demand.

help_brew() {
  cat <<EOF
settle Homebrew drift in the two Brewfiles

${c_bold}Usage${c_rst}
  ${DF} brew triage [--json]
  ${DF} brew decree ITEM.. (--global|--local|--ignore-global|--ignore-local)
                          [--reason TEXT] [--dry-run] [--no-push]
  ${DF} brew undecree ITEM.. [--dry-run] [--no-push]
  ${DF} brew merged
  ${DF} brew inventory [--json]
  ${DF} brew <subcommand> --help

  Declared state is two Brewfiles: global $(help::tilde "${GLOBAL_BREWFILE}")
  (git df, committed, never pushed by the tool) and local
  $(help::tilde "${LOCAL_BREWFILE}") (git ldf, committed and pushed).
  Nothing here touches brew's own state; the brew_pkgs step installs, the
  brew_drift step reports. ITEM is [formula:|cask:|tap:|vscode:]name; the kind
  may be omitted when exactly one kind matches.

${c_bold}Subcommands${c_rst}
  triage      describe undeclared, orphaned and duplicate items, with the
              commands that settle each
  decree      declare an item in a tier's Brewfile, or ignore it, and commit
  undecree    remove the lines decree wrote for the item, and commit
  merged      print the merged Brewfile (debugging)
  inventory   what is installed, from receipts

${c_bold}Flags${c_rst}
  --json      triage, inventory: JSON instead of text
  --dry-run   decree, undecree: print the lines, paths and git commands; touch
              nothing
  --no-push   decree, undecree: skip the local tier's push
  each subcommand's --help has the rest

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_GLOBAL_DIR)
      directory of the global Brewfile
      (default $(help::tilde "${ARI_DOTFILES_GLOBAL_DIR}"))
  $(ENV ARI_DOTFILES_LOCAL_DIR)
      directory of the local Brewfile
      (default $(help::tilde "${ARI_DOTFILES_LOCAL_DIR}"))
  $(ENV ARI_DOTFILES_NO_PUSH)
      1 skips the local tier's push after a decree commit
  $(ENV ARI_DOTFILES_BREW)
      the brew binary (default: probed on PATH, then under
      ARI_DOTFILES_BREW_PREFIXES)
EOF
}

cmd_brew() {
  need_lib "${ARI_DOTFILES_CMD}/brew/brew.zsh"
  need_lib "${ARI_DOTFILES_CMD}/brew/decree.zsh"
  local sub="${1:-}"
  [[ -n "${sub}" ]] || usage_error "brew needs a subcommand | known='triage decree undecree merged inventory'"
  shift
  # triage/decree/undecree parse their own flags and print their own --help.
  case "${sub}" in
    triage) decree::triage "$@"; return ;;
    decree) decree::decree "$@"; return ;;
    undecree) decree::undecree "$@"; return ;;
  esac
  local -a json=()
  zparseopts -D -F -K -- -json=json || usage_error "brew ${sub}: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "brew ${sub} takes no positional arguments | args='$*'"
  case "${sub}" in
    merged)
      local tmp
      tmp="$(mktemp)"
      brewfile::merge "${tmp}" "${GLOBAL_BREWFILE}" "${LOCAL_BREWFILE}"
      cat -- "${tmp}"
      rm -f -- "${tmp}"
      ;;
    inventory)
      if (( ${#json} )); then
        brew::inventory
        return 0
      fi
      brew::inventory | jq -r '
        ((.formulae // [])[] | select(.on_request) | "formula  \(.full_name)"),
        ((.casks // [])[] | select(.on_request) | "cask     \(.full_token)"),
        ((.taps // [])[] | "tap      \(.name)"),
        ((.vscode // [])[] | "vscode   \(.id)")'
      ;;
    *) usage_error "unknown brew subcommand | sub='${sub}' known='triage decree undecree merged inventory'" ;;
  esac
}
