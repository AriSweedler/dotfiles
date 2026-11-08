# Neovim: ~/.config/nvim is the committed config, copied from the store, and its plugins are
# start packages in ~/.local/share/nvim/site/pack/nix/start, each fetched at the commit
# nvim-pack-lock.json pins. Nothing at run time installs or updates a plugin: to move one, edit
# its rev in the lock file (or add an entry for a new plugin), commit, and `dotfiles switch`.
# Edit the config in ~/dotfiles/.config/nvim (developer.lua's mappings open it there).
# Writable state stays in ~/.local/share/nvim: treesitter parsers, and the spell words `zg` adds
# (site/spell, the first writable spell directory on the runtimepath).
{ lib, pkgs, src, ... }:
let
  config = "${src}/.config/nvim";
  lock = (lib.importJSON "${config}/nvim-pack-lock.json").plugins;
  plugin = name: pin: pkgs.vimUtils.buildVimPlugin {
    pname = name;
    version = builtins.substring 0 7 pin.rev;
    src = builtins.fetchGit {
      url = pin.src;
      inherit (pin) rev;
      allRefs = true;
    };
    dontBuild = true; # the plugins are Lua and Vimscript; a Makefile is for their own tests
    doCheck = false; # requiring each module needs the others and the user config
  };
in
lib.mkIf (builtins.pathExists "${config}/init.lua") {
  xdg.configFile."nvim".source = config;
  xdg.dataFile = lib.mapAttrs'
    (name: pin: lib.nameValuePair "nvim/site/pack/nix/start/${name}" { source = plugin name pin; })
    lock;
}
