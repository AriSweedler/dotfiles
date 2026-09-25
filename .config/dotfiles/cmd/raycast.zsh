# dotfiles/cmd/raycast.zsh — `dotfiles raycast`: Raycast in parity with the dotfiles. The router
# and both subsystems are the zsh plugins (raycast.zsh, raycast_link.zsh, raycast_snippets.zsh),
# which the interactive shell also loads; this verb only loads them and hands over.

help_raycast() {
  cat <<EOF
Raycast in parity with the dotfiles: allow-list, snippets

${c_bold}Usage${c_rst}
  ${DF} raycast link <slug|path> [--plain]
  ${DF} raycast link list | check | allow [--dry-run]
  ${DF} raycast snippets sync [--dry-run] | list | check | adopt
  ${DF} raycast snippets pull FILE | diff FILE | fmt
  ${DF} raycast snippets reset-manifest [NAME..]
  ${DF} raycast snippets move NAME --to shared|local
  ${DF} raycast sync [--dry-run]
  ${DF} raycast <subsystem> help

  Bindings live in karabiner.ts's tables and compile through bake; 'link'
  renders a Raycast action as a link with its Karabiner key and keeps
  Raycast's deeplink allow-list current. Snippets live in two files, merged
  with local winning by name:
    shared  ~/.config/raycast-snippets/snippets.json (git df, public)
    local   ~/.local/share/raycast-snippets/snippets.json (git ldf, private)
  One rule: personal data stays in the local tier; shared is for snippets
  safe in a public repo, plus fmt's placeholders. 'sync' runs every
  subsystem's sync in order; the raycast_sync step is its --dry-run.

${c_bold}Subcommands${c_rst}
  link <slug|path>   the widget <[Raycast: Title | key: '✦4'](raycast://…)>
  link list          every binding: slug, chords, title, deeplink
  link check         OK/MISSING per binding against the compiled karabiner.json
  link allow         write the missing allow-list ids to Raycast's plist
  snippets sync      import what is new or changed, one Raycast dialog a batch
  snippets list      state and tier of every snippet
  snippets check     placeholder parity between the tiers
  snippets adopt     seed the manifest from Raycast's current state
  snippets pull      a Raycast export is the truth; update the tier files
  snippets diff      the merged set against a Raycast export, by name
  snippets move      relocate one snippet between the tiers
  snippets fmt       canonical rewrite of both files, placeholders included
  snippets reset-manifest   forget names (all when none)
  sync               every subsystem's sync, in order

${c_bold}Flags${c_rst}
  --plain      link: the bare form, <Raycast: Title | key: '✦4'> url
  --dry-run    allow, sync, adopt, pull, fmt, move, reset-manifest: print the
               plan, change nothing
  --to TIER    move: shared or local

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
