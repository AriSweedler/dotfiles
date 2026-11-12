# open-any's openers: one list, ~/.config/open-any/openers (`name<TAB>path` lines, by name), that
# open-any reads instead of scanning both bin tiers for open-* executables. The shared openers
# are the clone's .config/bin/open-*, at their ~/.config/bin path. A local flake adds its own, and
# a name it defines replaces the shared one:
#
#   dotfiles.openAny.openers.open-ticket = "${config.home.homeDirectory}/.local/bin/open-ticket";
{ config, lib, src, ... }:
let
  home = config.home.homeDirectory;
  cfg = config.dotfiles.openAny.openers;
  dir = "${src}/.config/bin";
  sharedNames = lib.optionals (builtins.pathExists dir)
    (lib.attrNames (lib.filterAttrs (name: type: lib.hasPrefix "open-" name && name != "open-any" && type != "directory")
      (builtins.readDir dir)));
in
{
  options.dotfiles.openAny.openers = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "open-any openers by name (open-<kind>): the absolute path of each executable; a definition replaces a shared opener of the same name.";
  };

  config = {
    dotfiles.openAny.openers = lib.genAttrs sharedNames (n: lib.mkDefault "${home}/.config/bin/${n}");

    xdg.configFile."open-any/openers".text =
      lib.concatMapStrings (n: "${n}\t${cfg.${n}}\n") (lib.sort lib.lessThan (lib.attrNames cfg));
  };
}
