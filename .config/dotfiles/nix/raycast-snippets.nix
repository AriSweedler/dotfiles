# Raycast snippets: the shared tier (the repo's .config/raycast-snippets/snippets.json) and the
# local flake's file, merged here into ~/.config/raycast-snippets/merged.json, the one file
# `dotfiles raycast snippets` syncs into Raycast. The merge is lib/raycast-snippets-merge.nix (a
# local entry replaces a shared one by name); a duplicate name in one file or a keyword two
# snippets share fails the build. The local flake names its file:
#
#   programs.raycastSnippets.localFile = ./raycast-snippets.json;
{ config, lib, src, ... }:
let
  cfg = config.programs.raycastSnippets;
  home = config.home.homeDirectory;
  sharedSource = "${src}/.config/raycast-snippets/snippets.json";
  merged = import ./lib/raycast-snippets-merge.nix {
    tiers = [
      {
        label = "shared";
        path = "${home}/dotfiles/.config/raycast-snippets/snippets.json";
        source = if builtins.pathExists sharedSource then sharedSource else null;
      }
      {
        label = "local";
        path = "${home}/.local/share/dotfiles/nix/raycast-snippets.json";
        source = cfg.localFile;
      }
    ];
  };
in
{
  options.programs.raycastSnippets.localFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "This machine's private snippets: a JSON array in Raycast's import format, in the local flake.";
  };

  config = {
    assertions = map (message: { assertion = false; message = "raycast snippets: ${message}"; }) merged.errors;
    xdg.configFile."raycast-snippets/merged.json".text = builtins.toJSON merged.value;
  };
}
