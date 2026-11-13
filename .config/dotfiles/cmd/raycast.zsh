# dotfiles/cmd/raycast.zsh — `dotfiles raycast`: Raycast in parity with the dotfiles. The router
# and both subsystems are the zsh plugins (raycast.zsh, raycast_link.zsh, raycast_snippets.zsh),
# which the interactive shell also loads; this verb declares the help, loads them and hands over:
# the plugins parse their own words (they run in shells without the harness libraries).

verb::define raycast 'Raycast in parity with the dotfiles: bindings, snippets'
verb::usage raycast 'raycast link BINDING|DEEPLINK [--plain]' \
  'raycast link list | check | prime [BINDING..] | unprimed | undocumented' \
  'raycast link edit [BINDING]' \
  'raycast snippets sync [--dry-run] [--deleted] | list | check | adopt' \
  'raycast snippets pull RAYCAST_EXPORT | diff RAYCAST_EXPORT | fmt' \
  'raycast snippets reset-manifest [SNIPPET..]' \
  'raycast snippets move SNIPPET --to TIER' \
  'raycast snippets edit [--local|--shared] | undocumented' \
  'raycast sync [--dry-run]' \
  'raycast undocumented' \
  'raycast <subsystem> help'
verb::about raycast <<'EOF'
Bindings live in karabiner.ts's tables and compile through bake; 'link'
renders a Raycast action as a link with its Karabiner key; 'link prime'
opens each bound command once so its "Always allow" is clicked. Snippets live in two files, merged
with local winning by name:
  shared  ~/dotfiles/.config/raycast-snippets/snippets.json (git df, public)
  local   ~/.local/share/dotfiles/nix/raycast-snippets.json (git ldf, private)
  Nix merges them into ~/.config/raycast-snippets/merged.json; after an edit: commit, dotfiles switch, sync.
One rule: personal data stays in the local tier; shared is for snippets
safe in a public repo. A local-only snippet is fine. 'sync' runs every
subsystem's sync in order; the raycast_sync step is its --dry-run.
EOF
verb::section raycast 'Documentation rule' <<'EOF'
Every binding and snippet says what it does in one line. A binding's
deeplink(…) takes a description option (its title does not count); a
snippet's winning entry has a "description" field (a local override
documents its placeholder's name), which Raycast never sees. The
raycast_sync step fails, manual, on one without, naming the edit that
fixes each.
EOF
verb::sub raycast link "link BINDING|DEEPLINK: the widget <[Raycast: Title | key: '✦4'](raycast://…)>; alone: the bindings' usage"
verb::sub raycast 'link list' 'every binding: slug, chords, title, deeplink'
verb::sub raycast 'link check' 'OK/MISSING per binding against the compiled karabiner.json'
verb::sub raycast 'link prime' 'open each bound command (or the slugs given) in turn, Enter between, to click "Always allow" once each; needs a terminal; records each answered slug'
verb::sub raycast 'link unprimed' 'a warn naming the bindings never primed on this machine, with the prime that fixes it (a sync step)'
verb::sub raycast 'link edit' "the table holding the slug's deeplink in \\\$EDITOR at its line (no slug: raycast_shortcuts.ts); on save the generator and every chord are checked; no commit, bake compiles it; an invalid table is reported, left as edited (on a terminal, offered for another edit); also: link --edit"
verb::sub raycast 'link undocumented' 'every binding without a description, with its fix'
verb::sub raycast snippets "the snippets; alone: their usage"
verb::sub raycast 'snippets sync' 'import what is new or changed, one Raycast dialog a batch'
verb::sub raycast 'snippets list' 'state and tier of every snippet'
verb::sub raycast 'snippets check' 'warn per shared placeholder nothing overrides'
verb::sub raycast 'snippets adopt' "seed the manifest from Raycast's current state"
verb::sub raycast 'snippets pull' 'a Raycast export is the truth; update the tier files'
verb::sub raycast 'snippets diff' 'the merged set against a Raycast export, by name'
verb::sub raycast 'snippets move' 'relocate one snippet between the tiers'
verb::sub raycast 'snippets fmt' 'canonical rewrite of both files, adds no placeholders'
verb::sub raycast 'snippets reset-manifest' 'forget names (all when none)'
verb::sub raycast 'snippets edit' 'a tier file in \$EDITOR, then validate (and the doc rule for the names it wins), fmt, next step; also: snippets --edit'
verb::sub raycast 'snippets undocumented' 'every snippet without a description, with its fix'
verb::sub raycast sync "every subsystem's sync, in order"
verb::sub raycast undocumented "every subsystem's undocumented units"
verb::sub raycast 'edit link' "the same as link edit"
verb::sub raycast 'edit snippets' "the same as snippets edit"
verb::arg raycast --for link 'BINDING|DEEPLINK'
verb::arg raycast --for 'link prime' '[BINDING..]'
verb::arg raycast --for 'link edit, edit link' '[BINDING]'
verb::arg raycast --for 'snippets pull, snippets diff' 'RAYCAST_EXPORT'
verb::arg raycast --for 'snippets reset-manifest' '[SNIPPET..]'
verb::arg raycast --for 'snippets move' 'SNIPPET'
verb::edit raycast raycast::edit_cmd '[link [BINDING] | snippets [--local|--shared]]' \
  "a subsystem's edit; no target: pick one on a terminal (snippets local, snippets shared, bindings), otherwise the targets are listed, exit 64"
verb::flag raycast '--plain' "link: the bare form, <Raycast: Title | key: '✦4'> url" --for 'link'
verb::flag raycast '--dry-run' 'sync, adopt, pull, fmt, move, reset-manifest: print the plan, change nothing' --for 'sync, snippets sync, snippets adopt, snippets pull, snippets fmt, snippets move, snippets reset-manifest'
verb::flag raycast '--deleted' 'snippets sync: the old copies of the changed and removed snippets are gone from Raycast; import the changes' --for 'snippets sync'
verb::flag raycast '--to TIER' 'move: shared or local' --for 'snippets move'
verb::flag raycast '--local' 'edit: open the local tier file (the default)' --for 'snippets edit, edit snippets, edit'
verb::flag raycast '--shared' 'edit: open the shared tier file' --for 'snippets edit, edit snippets, edit'
verb::env raycast ARI_DOTFILES_RAYCAST_APP "Raycast's app bundle; absent = sync skips" '/Applications/Raycast.app'
verb::env raycast ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS 'the karabiner.ts checkout whose generator prints the bindings' '~/dotfiles/.config/karabiner/karabiner.ts'
verb::env raycast ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON "the compiled karabiner.json that 'link check' verifies against" '~/.config/karabiner/karabiner.json'
verb::env raycast ARI_DOTFILES_RAYCAST_SNIPPETS_SHARED_FILE 'the shared snippets file' '~/dotfiles/.config/raycast-snippets/snippets.json'
verb::env raycast ARI_DOTFILES_RAYCAST_SNIPPETS_LOCAL_FILE 'the local snippets file, in the local flake' '~/.local/share/dotfiles/nix/raycast-snippets.json'
verb::env raycast ARI_DOTFILES_RAYCAST_SNIPPETS_MERGED "Nix's merge of the two, what sync imports" '~/.config/raycast-snippets/merged.json'
verb::env raycast ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST 'what has been imported, by name' '~/.local/share/raycast-snippets/manifest.json'

# raycast::load: the plugins, which need jq and defaults.
raycast::load() {
  check_prerequisites jq defaults || exit 1
  need_lib "${ARI_DOTFILES_CONFIG}/zsh/plugins/raycast.zsh"
}

# The plugins parse their own words; verb::parse first refuses a flag the declaration lacks, or one
# with a subcommand that does not take it, so what completes is what runs.
cmd_raycast() {
  local -A opts; local -a args
  verb::parse raycast "$@"
  raycast::load; ari_raycast "$@"
}

# `raycast edit …` and `raycast --edit …`: the router's own edit.
raycast::edit_cmd() { raycast::load; ari_raycast edit "$@"; }
