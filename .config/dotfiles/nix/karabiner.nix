# Karabiner-Elements: ~/.config/karabiner/karabiner.json is the committed file, copied from the
# store. `karabiner/bin/bake` compiles karabiner.ts into the clone's copy; commit it, and the next
# `dotfiles switch` makes it live. The rest of the directory stays writable (Karabiner keeps
# automatic_backups/ there). A change saved in Karabiner's own settings window replaces the link
# with a file, which the next switch moves aside as karabiner.json.before-nix: put it in
# karabiner.ts instead.
{ lib, src, ... }:
let file = "${src}/.config/karabiner/karabiner.json";
in
lib.mkIf (builtins.pathExists file) {
  xdg.configFile."karabiner/karabiner.json".source = file;
}
