# Phase 4a bridge: every file the shared repo tracks, linked from HOME into the plain clone at
# ~/dotfiles. The clone is the only copy, so an edit there is live without a switch; phase 4 then
# moves one tool at a time from these links to a module or a store copy.
#
# `src` is the repo as the flake input holds it: exactly the tracked files. It is only read for
# their names; each link points at the clone, never at the store. With the `path:` input of the
# nix directory alone (the layout before the clone) it holds no repo, and this module adds nothing.
{ config, lib, src, ... }:
let
  clone = "${config.home.homeDirectory}/dotfiles";

  # Linked as whole directories, not file by file: tools write files into them (nvim's
  # lazy-lock.json, Karabiner's karabiner.json, Claude Code's skills), and the submodules are
  # repos of their own.
  wholeDirs = [
    ".config/nvim"
    ".config/karabiner"
    ".config/claude"
    ".config/chrome-exoskeleton"
    ".config/plugged"
  ];
  # The repo's own files, not config HOME reads.
  skipped = [ "README.md" ".gitmodules" ".gitignore" ];

  # Repo-relative paths of every tracked file (a tracked symlink included) outside wholeDirs.
  walk = rel:
    lib.concatLists (lib.mapAttrsToList
      (name: type:
        let path = if rel == "" then name else "${rel}/${name}";
        in
        if lib.elem path wholeDirs || lib.elem path skipped then [ ]
        else if type == "directory" then walk path
        else [ path ])
      (builtins.readDir "${src}/${rel}"));

  link = path: lib.nameValuePair path {
    source = config.lib.file.mkOutOfStoreSymlink "${clone}/${path}";
  };
in
lib.mkIf (builtins.pathExists "${src}/.config/dotfiles/nix/bridge.nix") {
  home.file = lib.listToAttrs (map link (walk "" ++ wholeDirs));
}
