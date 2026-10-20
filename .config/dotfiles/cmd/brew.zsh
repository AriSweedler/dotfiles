# dotfiles/cmd/brew.zsh — `dotfiles brew`: the declared-state side of Homebrew. The brew model
# (cmd/brew/brew.zsh), the decree editor (cmd/brew/decree.zsh) and the hand editor
# (cmd/brew/edit.zsh) are loaded on demand; each parses its flags with `verb::parse brew`.

verb::define brew 'settle Homebrew drift in the two Brewfiles'
verb::usage brew 'brew triage [--json]' 'brew triage (--interactive | --edit [FILE]) [--dry-run] [--no-push]' \
  'brew decree ITEM.. TIER --reason TEXT [--dry-run] [--no-push]' \
  'brew undecree ITEM.. [--dry-run] [--no-push]' 'brew merged' 'brew inventory [--json]'
verb::about brew <<'EOF'
Declared state is two Brewfiles: global $(help::tilde "${GLOBAL_BREWFILE}")
(git df, committed, never pushed by the tool) and local
$(help::tilde "${LOCAL_BREWFILE}") (git ldf, committed and pushed).
Nothing here touches brew's own state; the brew_pkgs step installs, the
brew_drift step reports. ITEM is [formula:|cask:|tap:|vscode:]name; the kind
may be omitted when exactly one kind matches. TIER is one of --global,
--local, --ignore-global and --ignore-local.

Every entry says why it is there: a Brewfile line by a trailing '# why' or a
heading comment opening its paragraph (lines between blank lines; a
commented-out entry is no heading; in the decree block only the trailing
comment counts), an ignore line by its '# reason'. brew_drift fails as
undocumented otherwise.
EOF
verb::sub brew triage 'list every installed item (formula, cask, tap, VS Code extension) that neither Brewfile declares, with the three decree commands that settle it, then orphaned kegs, duplicates, declared orphans, the ignore list and classifier notes; it describes and never recommends a tier'
verb::sub brew decree "copy the installed item's declaration (the verbatim 'brew bundle dump' line) into TIER's Brewfile decree block and commit it; --ignore-global and --ignore-local record it in that tier's Brewfile.ignore instead. A third-party tap the item needs is declared alongside, trusted, with '# feeds ITEM'. Refuses items already declared, orphaned or not installed; never installs, uninstalls or calls 'brew bundle add'"
verb::sub brew undecree "remove the lines decree wrote for the item from whichever tier holds them (Brewfile or Brewfile.ignore, decree block only; hand-placed lines are reported and left alone), drop the tap line when nothing else in that tier uses the tap, and commit"
verb::sub brew merged 'print the merged Brewfile (debugging)'
verb::sub brew inventory 'what is installed, from receipts'
verb::edit brew brew::edit_cmd '[--global|--local] [--ignore] [--no-commit] [--no-push]' \
  "open a tier's Brewfile (with --ignore, its Brewfile.ignore) in \\\$EDITOR. On save it must parse (a Brewfile through 'brew bundle list'; an ignore file as '<formula|cask|tap|vscode> <name>  # reason' and 'include-declared <abs path>  # reason' lines) and say why for every entry; a file that passes is committed in its tier, the subject naming each item added or removed, and one that does not is reported line by line and left as edited, uncommitted. Nothing is installed or uninstalled"
verb::flag brew '--json' 'triage, inventory: JSON instead of text (triage: drift.json)'
verb::flag brew '--interactive' 'triage: pick a tier and give a reason per undeclared item, confirm the grouped plan once, then run one decree (one commit) per group; needs a terminal on stdin and stdout'
verb::flag brew '--edit [FILE]' "triage: write the undeclared items to a plan file, one 'skip kind:name' line each, and open it in \\\$EDITOR; change each skip to global add, local add, global ignore or local ignore (each ending in '# reason', kept as the line's comment), or to delete (uninstall it here). On save the plan runs as --interactive's does, then the uninstalls; a bad line is reported by number and the file kept. FILE resumes that plan file"
verb::flag brew '--global' "decree: declare the item in the shared Brewfile; edit: open the shared tier's file"
verb::flag brew '--local' "decree: declare the item in the local Brewfile; edit: open the local tier's file (the default)"
verb::flag brew '--ignore-global' 'decree: record the item in the shared Brewfile.ignore'
verb::flag brew '--ignore-local' 'decree: record the item in the local Brewfile.ignore'
verb::flag brew '--reason TEXT' "decree: required; why the item is declared or ignored, written as each line's trailing '# TEXT' comment (brew_drift fails an entry without one)"
verb::flag brew '--ignore' "edit: the tier's Brewfile.ignore instead of its Brewfile"
verb::flag brew '--no-commit' 'edit: check the file, leave it uncommitted'
verb::flag brew '--dry-run' 'triage (with --interactive or --edit): every decree prints instead of writing; decree, undecree: print the lines, paths and git commands, touch nothing'
verb::flag brew '--no-push' "triage (with --interactive or --edit), decree, undecree, edit: skip the local tier's push"
verb::env brew ARI_DOTFILES_GLOBAL_DIR 'directory of the global Brewfile' '$(help::tilde "${ARI_DOTFILES_GLOBAL_DIR}")'
verb::env brew ARI_DOTFILES_LOCAL_DIR 'directory of the local Brewfile' '$(help::tilde "${ARI_DOTFILES_LOCAL_DIR}")'
verb::env brew ARI_DOTFILES_NO_PUSH "1 skips the local tier's push after a decree, undecree or edit commit"
verb::env brew ARI_DOTFILES_BREW 'the brew binary; unset, it is probed on PATH, then under ARI_DOTFILES_BREW_PREFIXES'
verb::env brew EDITOR 'the editor edit and triage --edit open' 'vi'
verb::section brew 'Exit codes' <<'EOF'
triage    0 nothing undeclared, orphaned or duplicated; 1 otherwise; 2 brew is
          busy. --interactive: 0 every decree ran; 1 one refused or the plan
          was declined; 130 cancelled; 64 without a terminal. --edit: 0 every
          decree ran or nothing was chosen; 1 a bad line, a refused decree or
          a declined plan
decree    0 done; 1 refused or did not take; 2 brew is busy
undecree  0 done; 1 nothing decreed for the item; 2 brew is busy
edit      0 saved, or no change; 1 the file does not parse, an entry lacks its
          why, the editor failed or the commit was refused
any       64 usage
EOF

# The brew model, the decree editor and the hand editor, in that order.
brew::load() {
  need_lib "${ARI_DOTFILES_CMD}/brew/brew.zsh" || return 3
  need_lib "${ARI_DOTFILES_CMD}/brew/decree.zsh" || return 3
  need_lib "${ARI_DOTFILES_CMD}/brew/edit.zsh" || return 3
}

brew::edit_cmd() { brew::load || return 3; brewedit::edit "$@"; }

# brew::only SUB FLAG..: a usage error when the caller's `opts` holds a flag SUB does not take
# (verb::parse accepts every flag of the verb).
brew::only() {
  local sub="${1}" flag; shift
  for flag in "${(@k)opts}"; do
    (( ${@[(Ie)${flag}]} )) || usage_error "brew ${sub} does not take ${flag} | takes='${*:-no flags}'"
  done
}

cmd_brew() {
  brew::load || return 3
  local sub="${1:-}"
  [[ -n "${sub}" ]] || usage_error "brew needs a subcommand | known='triage decree undecree edit merged inventory'"
  shift
  # triage, decree and undecree parse their own line: triage hands decree its groups' words.
  case "${sub}" in
    triage) decree::triage "$@"; return ;;
    decree) decree::decree "$@"; return ;;
    undecree) decree::undecree "$@"; return ;;
    edit) brewedit::edit "$@"; return ;;
    merged|inventory) ;;
    *) usage_error "unknown brew subcommand | sub='${sub}' known='triage decree undecree edit merged inventory'" ;;
  esac
  local -A opts; local -a args
  verb::parse brew "$@"
  (( ${#args} == 0 )) || usage_error "brew ${sub} takes no positional arguments | args='${args[*]}'"
  case "${sub}" in
    merged)
      brew::only merged
      local tmp
      tmp="$(mktemp)"
      brewfile::merge "${tmp}" "${GLOBAL_BREWFILE}" "${LOCAL_BREWFILE}"
      cat -- "${tmp}"
      rm -f -- "${tmp}"
      ;;
    inventory)
      brew::only inventory --json
      if (( ${+opts[--json]} )); then
        brew::inventory
        return 0
      fi
      brew::inventory | jq -r '
        ((.formulae // [])[] | select(.on_request) | "formula  \(.full_name)"),
        ((.casks // [])[] | select(.on_request) | "cask     \(.full_token)"),
        ((.taps // [])[] | "tap      \(.name)"),
        ((.vscode // [])[] | "vscode   \(.id)")'
      ;;
  esac
}
