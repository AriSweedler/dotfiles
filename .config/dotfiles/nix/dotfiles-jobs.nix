# The dotfiles jobs framework's one set of plugins and deps: ~/.config/dotfiles-jobs/plugins/<name>
# and ~/.config/dotfiles-jobs/deps/<name>, one link per name, built here instead of the framework
# scanning both tiers at run time. Each link points at the editable file (the clone's
# .config/dotfiles/{jobs,deps}/<name>, or the local tier's), not at the store, so an edit is live
# at once; a new or removed plugin needs a switch. A local flake adds its own, and a name it
# defines replaces the shared one:
#
#   dotfiles.jobs.plugins.sync = "${config.home.homeDirectory}/.local/share/dotfiles/jobs/sync";
#   dotfiles.jobs.deps.node = "${config.home.homeDirectory}/.local/share/dotfiles/deps/node";
{ config, lib, src, ... }:
let
  home = config.home.homeDirectory;
  cfg = config.dotfiles.jobs;
  # The shared tier's plugins (or deps): every file in the directory but its README, at the clone.
  shared = sub:
    let dir = "${src}/.config/dotfiles/${sub}";
    in lib.optionalAttrs (builtins.pathExists dir)
      (lib.mapAttrs (name: _: lib.mkDefault "${home}/dotfiles/.config/dotfiles/${sub}/${name}")
        (lib.filterAttrs (name: type: type == "regular" && !lib.hasSuffix ".md" name) (builtins.readDir dir)));
  links = sub: set: lib.mapAttrs'
    (name: path: lib.nameValuePair ".config/dotfiles-jobs/${sub}/${name}" {
      source = config.lib.file.mkOutOfStoreSymlink path;
    })
    set;
  option = what: lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "dotfiles jobs ${what} by name: the absolute path of each editable file; a definition replaces a shared one of the same name.";
  };
in
{
  options.dotfiles.jobs = {
    plugins = option "plugins";
    deps = option "deps";
  };

  config = {
    dotfiles.jobs.plugins = shared "jobs";
    dotfiles.jobs.deps = shared "deps";
    home.file = links "plugins" cfg.plugins // links "deps" cfg.deps;
  };
}
