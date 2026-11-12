# zsh's plugins: one ordered list, ~/.config/zsh/plugins.list.zsh, that .zshrc sources instead of
# scanning both tiers' plugin directories at every shell start. Each line sources the editable
# file (the clone's .config/zsh/plugins/<name>.zsh, or the local tier's), so an edit is live in
# the next shell; a new or removed plugin needs a switch. Order: the shared plugins by name, then
# the local ones by name. A local flake adds its own, and a name it defines replaces the shared
# one in the shared one's place:
#
#   dotfiles.zsh.plugins.gws = "${config.home.homeDirectory}/.local/share/zsh/plugins/gws.zsh";
#
# A *.secret.zsh file is listed the same way; it is untracked, so the path is only a string here
# and a missing file is skipped at start (source_file checks it is readable).
{ config, lib, src, ... }:
let
  home = config.home.homeDirectory;
  cfg = config.dotfiles.zsh.plugins;
  dir = "${src}/.config/zsh/plugins";
  # Every *.zsh in the directory but the test suites, which guard themselves and are run_tests'.
  sharedNames = lib.optionals (builtins.pathExists dir)
    (lib.sort lib.lessThan (map (lib.removeSuffix ".zsh") (lib.attrNames (lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".zsh" name && !lib.hasSuffix ".test.zsh" name)
      (builtins.readDir dir)))));
  localNames = lib.sort lib.lessThan (lib.filter (n: !lib.elem n sharedNames) (lib.attrNames cfg));
  ordered = lib.filter (n: cfg ? ${n}) sharedNames ++ localNames;
in
{
  options.dotfiles.zsh.plugins = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "zsh plugins by name: the absolute path of each file .zshrc sources; a definition replaces a shared plugin of the same name.";
  };

  config = {
    dotfiles.zsh.plugins = lib.listToAttrs (map
      (n: lib.nameValuePair n (lib.mkDefault "${home}/dotfiles/.config/zsh/plugins/${n}.zsh"))
      sharedNames);

    xdg.configFile."zsh/plugins.list.zsh".text = ''
      # Written by ~/.config/dotfiles/nix/zsh-plugins.nix: the plugins .zshrc sources, in order.
    '' + lib.concatMapStrings (n: "source_file ${lib.escapeShellArg cfg.${n}}\n") ordered;
  };
}
