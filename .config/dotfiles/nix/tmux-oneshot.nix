# tmux-oneshot's menu: one file, ~/.config/tmux_oneshot/entries.json, merged here by the module
# system instead of by the script. The shared entries are the JSON lists under
# .config/tmux_oneshot/ in the repo, in menu order (macos.json only on a Mac, linux.json only on
# Linux, desktop.json only on a machine with a desktop). A local flake adds its own, or replaces a
# shared one by name:
#
#   programs.tmuxOneshot.entries.deploy = { cmd = "deploy-it"; menu.text = "…"; key = "ctrl-p"; };
#   programs.tmuxOneshot.files = [ ./tmux_oneshot/work.json ];   # JSON lists, after the shared ones
#
# An entry's name is its menu.name, else its cmd. `order` sorts the menu (shared entries count
# from 0, local ones default to 1000) and is dropped from the file. Two entries with one direct
# key fail the build. The generated tier (vi_/ and other shell plugins) stays at run time.
{ config, lib, pkgs, src, ... }:
let
  cfg = config.programs.tmuxOneshot;
  sharedDir = "${src}/.config/tmux_oneshot";
  sharedFiles = lib.optionals (builtins.pathExists sharedDir)
    (map (f: "${sharedDir}/${f}") (lib.sort lib.lessThan
      (lib.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".json" n && forThisPlatform n)
        (builtins.readDir sharedDir)))));
  # A shared file named for a platform is read only there: macos.json holds Mac commands
  # (killall NotificationCenter, applepaste, Raycast links), which a Linux menu must not offer.
  # desktop.json is for a machine with a desktop to open things on (programs.tmuxOneshot.desktop).
  platformFiles = {
    "macos.json" = pkgs.stdenv.hostPlatform.isDarwin;
    "linux.json" = pkgs.stdenv.hostPlatform.isLinux;
    "desktop.json" = cfg.desktop;
  };
  forThisPlatform = n: platformFiles.${n} or true;
  nameOf = e: e.menu.name or e.cmd;
  # A list of entries as name → entry, each carrying its position from `base` on.
  fromList = base: list: lib.listToAttrs (lib.imap0
    (i: e: lib.nameValuePair (nameOf e) ({ order = base + i; } // e)) list);

  # An entry defined by attribute name alone gets that name as its menu.name.
  named = name: e: if nameOf' e == name then e else e // { menu = (e.menu or { }) // { inherit name; }; };
  nameOf' = e: e.menu.name or e.cmd or null;
  orderOf = e: e.order or 1000;
  sorted = lib.sort (a: b: if orderOf a != orderOf b then orderOf a < orderOf b else nameOf a < nameOf b)
    (lib.mapAttrsToList named cfg.entries);
  entries = map (e: removeAttrs e [ "order" ]) sorted;
  keys = lib.filter (k: k != null) (map (e: e.key or null) entries);
  duplicateKeys = lib.unique (lib.filter (k: lib.count (x: x == k) keys > 1) keys);
in
{
  options.programs.tmuxOneshot = {
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "tmux-oneshot menu entries by name; a definition replaces a shared entry of the same name.";
    };
    desktop = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      description = "Whether this machine has a desktop (a browser, apps to open): desktop.json's entries are offered only then. A Mac has one; a Linux machine says so itself.";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "JSON lists of entries, added after the shared ones in order.";
    };
  };

  config = {
    programs.tmuxOneshot.entries = lib.mkMerge [
      (lib.mapAttrs (_: lib.mkDefault) (fromList 0 (lib.concatMap lib.importJSON sharedFiles)))
      (fromList 1000 (lib.concatMap lib.importJSON cfg.files))
    ];

    assertions = [{
      assertion = duplicateKeys == [ ];
      message = "tmux-oneshot: direct key used by more than one entry: ${lib.concatStringsSep ", " duplicateKeys}";
    }];

    xdg.configFile."tmux_oneshot/entries.json".source =
      (pkgs.formats.json { }).generate "tmux-oneshot-entries.json" entries;
  };
}
