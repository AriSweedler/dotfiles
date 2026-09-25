# dotfiles/cmd/raycast.zsh — `dotfiles raycast`: Raycast in parity with the dotfiles. The router
# and both subsystems are the zsh plugins (raycast.zsh, raycast_link.zsh, raycast_snippets.zsh),
# which the interactive shell also loads; this verb only loads them and hands over.

help_raycast() {
  cat <<EOF
dotfiles raycast link|snippets|sync   Raycast in parity with the dotfiles: the deeplink allow-list, the versioned snippets

  dotfiles raycast link <slug|path> [--plain]     a Raycast action as a link with its Karabiner key
  dotfiles raycast link list | check | allow [--dry-run]
  dotfiles raycast snippets sync [--dry-run] | list | check | adopt | pull FILE | diff FILE
                          | move NAME --to shared|local | fmt | reset-manifest [NAME...]
  dotfiles raycast sync [--dry-run]               every subsystem's sync, in order
  dotfiles raycast <subsystem> help               that subsystem's usage

  Bindings live in karabiner.ts's tables and compile through bake. Snippets live in two files,
  merged with local winning by name: shared ~/.config/raycast-snippets/snippets.json (git df,
  public remote) and local ~/.local/share/raycast-snippets/snippets.json (git ldf, private). One
  rule: personal data stays in the local tier; shared is for snippets safe in a public repo, plus
  fmt's placeholders. The raycast_sync step is 'dotfiles raycast sync --dry-run'.
EOF
}

cmd_raycast() {
  check_prerequisites jq defaults || exit 1
  need_lib "${DOTFILES_CONFIG}/zsh/plugins/raycast.zsh"
  ari_raycast "$@"
}
