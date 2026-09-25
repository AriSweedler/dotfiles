# dotfiles/cmd/brew.zsh — `dotfiles brew`: the declared-state side of Homebrew. The brew model
# (cmd/brew/brew.zsh) and the decree editor (cmd/brew/decree.zsh) are loaded on demand.

help_brew() {
  cat <<EOF
dotfiles brew triage|decree|undecree|merged|inventory   settle Homebrew drift in the two Brewfiles

  dotfiles brew triage   [--json]                describe undeclared, orphaned and duplicate items
  dotfiles brew decree   ITEM.. (--global|--local|--ignore-global|--ignore-local) [--reason TEXT] [--dry-run] [--no-push]
                                                 declare an item in a tier's Brewfile (or ignore it), and commit
  dotfiles brew undecree ITEM.. [--dry-run] [--no-push]
  dotfiles brew merged                           print the merged Brewfile (debugging)
  dotfiles brew inventory [--json]               what is installed, from receipts

  ITEM = [formula:|cask:|tap:|vscode:]name; the kind prefix may be omitted when exactly one kind matches.
  Tiers: global ${GLOBAL_BREWFILE} (git df, committed, never pushed by the tool)
         local  ${LOCAL_BREWFILE} (git ldf, committed and pushed)
  Nothing here touches brew's own state; the brew_pkgs step installs, the brew_drift step reports.
EOF
}

cmd_brew() {
  need_lib "${DOTFILES_CMD}/brew/brew.zsh"
  need_lib "${DOTFILES_CMD}/brew/decree.zsh"
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
