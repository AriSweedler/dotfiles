# tmuxinator projects: every one in ~/.config/tmuxinator, placed here. The shared ones are the
# repo's .config/tmuxinator/*.yml; a local flake adds or replaces one by name:
#
#   programs.tmuxinatorProjects.work = ./tmuxinator/work.yml;
{ config, lib, src, ... }:
let
  sharedDir = "${src}/.config/tmuxinator";
  shared = lib.optionalAttrs (builtins.pathExists sharedDir)
    (lib.mapAttrs' (f: _: lib.nameValuePair (lib.removeSuffix ".yml" f) (lib.mkDefault "${sharedDir}/${f}"))
      (lib.filterAttrs (f: t: t == "regular" && lib.hasSuffix ".yml" f) (builtins.readDir sharedDir)));
in
{
  options.programs.tmuxinatorProjects = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = "tmuxinator projects by name; a definition replaces a shared project of the same name.";
  };

  config = {
    programs.tmuxinatorProjects = shared;
    xdg.configFile = lib.mapAttrs' (name: file: lib.nameValuePair "tmuxinator/${name}.yml" { source = file; })
      config.programs.tmuxinatorProjects;
  };
}
