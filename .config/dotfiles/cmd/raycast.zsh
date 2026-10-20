# dotfiles/cmd/raycast.zsh — `dotfiles raycast`: Raycast in parity with the dotfiles. The router
# and both subsystems are the zsh plugins (raycast.zsh, raycast_link.zsh, raycast_snippets.zsh),
# which the interactive shell also loads; this verb only loads them and hands over.

help_raycast() {
  cat <<EOF
Raycast in parity with the dotfiles: allow-list, snippets

${c_bold}Usage${c_rst}
  ${DF} raycast link <slug|path> [--plain]
  ${DF} raycast link list | check | allow [--dry-run] | undocumented
  ${DF} raycast link edit [<slug>]
  ${DF} raycast snippets sync [--dry-run] | list | check | adopt
  ${DF} raycast snippets pull FILE | diff FILE | fmt
  ${DF} raycast snippets reset-manifest [NAME..]
  ${DF} raycast snippets move NAME --to shared|local
  ${DF} raycast snippets edit [--local|--shared] | undocumented
  ${DF} raycast edit [link [<slug>] | snippets [--local|--shared]]
  ${DF} raycast --edit [link [<slug>] | snippets [--local|--shared]]
  ${DF} raycast sync [--dry-run]
  ${DF} raycast undocumented
  ${DF} raycast <subsystem> help

  Bindings live in karabiner.ts's tables and compile through bake; 'link'
  renders a Raycast action as a link with its Karabiner key and keeps
  Raycast's deeplink allow-list current. Snippets live in two files, merged
  with local winning by name:
    shared  ~/.config/raycast-snippets/snippets.json (git df, public)
    local   ~/.local/share/raycast-snippets/snippets.json (git ldf, private)
  One rule: personal data stays in the local tier; shared is for snippets
  safe in a public repo. A local-only snippet is fine. 'sync' runs every
  subsystem's sync in order; the raycast_sync step is its --dry-run.

  Documentation rule: every binding and snippet says what it does in one
  line. A binding's deeplink(…) takes a description option (its title does
  not count); a snippet's winning entry has a "description" field (a local
  override documents its placeholder's name), which Raycast never sees. The
  raycast_sync step fails, manual, on one without, naming the edit that
  fixes each.

${c_bold}Subcommands${c_rst}
  link <slug|path>   the widget <[Raycast: Title | key: '✦4'](raycast://…)>
  link list          every binding: slug, chords, title, deeplink
  link check         OK/MISSING per binding against the compiled karabiner.json
  link allow         write the missing allow-list ids to Raycast's plist
  link edit          the table holding the slug's deeplink in \$EDITOR at its
                     line (no slug: raycast_shortcuts.ts); on save the
                     generator and every chord are checked; no commit, bake
                     compiles it; an invalid table is reported, left as
                     edited (on a terminal, offered for another edit)
  link undocumented  every binding without a description, with its fix
  snippets sync      import what is new or changed, one Raycast dialog a batch
  snippets list      state and tier of every snippet
  snippets check     warn per shared placeholder nothing overrides
  snippets adopt     seed the manifest from Raycast's current state
  snippets pull      a Raycast export is the truth; update the tier files
  snippets diff      the merged set against a Raycast export, by name
  snippets move      relocate one snippet between the tiers
  snippets fmt       canonical rewrite of both files, adds no placeholders
  snippets reset-manifest   forget names (all when none)
  snippets edit      a tier file in \$EDITOR, then validate (and the doc rule
                     for the names it wins), fmt, next step
  snippets undocumented   every snippet without a description, with its fix
  edit               a subsystem's edit; no target: pick one on a terminal
                     (snippets local, snippets shared, bindings), otherwise
                     the targets are listed, exit 64
  sync               every subsystem's sync, in order
  undocumented       every subsystem's undocumented units

${c_bold}Flags${c_rst}
  --plain      link: the bare form, <Raycast: Title | key: '✦4'> url
  --dry-run    allow, sync, adopt, pull, fmt, move, reset-manifest: print the
               plan, change nothing
  --to TIER    move: shared or local
  --edit       the other spelling of edit, for raycast, link and snippets
  --local      edit: open the local tier file (the default)
  --shared     edit: open the shared tier file

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_RAYCAST_APP)
      Raycast's app bundle; absent = sync skips
      (default /Applications/Raycast.app)
  $(ENV ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS)
      the karabiner.ts checkout whose generator prints the bindings
      (default ~/.config/karabiner/karabiner.ts)
  $(ENV ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON)
      the compiled karabiner.json that 'link check' verifies against
      (default ~/.config/karabiner/karabiner.json)
  $(ENV ARI_DOTFILES_RAYCAST_SNIPPETS_DIRS)
      colon-separated snippet tiers, the last one local
      (default ~/.config/raycast-snippets:~/.local/share/raycast-snippets)
  $(ENV ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST)
      what has been imported, by name (default <local tier>/manifest.json)
EOF
}

cmd_raycast() {
  check_prerequisites jq defaults || exit 1
  need_lib "${ARI_DOTFILES_CONFIG}/zsh/plugins/raycast.zsh"
  ari_raycast "$@"
}
