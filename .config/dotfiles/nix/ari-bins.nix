# Ari's packaged bins, placed where the clone's copies were linked: ~/.config/bin/<name> now
# points into the store, so every caller that names that path (/ari-driving, a remote host's
# run_log) keeps working, and the bridge skips the clone's file. An edit to one reaches HOME at
# the next `dotfiles switch` (package what you run, link what you edit).
{ lib, pkgs, src, ... }:
let
  ari = import ./pkgs { inherit pkgs src; };
  # package → its bins under .config/bin
  placed = {
    run-log = [ "run_log" "run_log-capture.py" "irun" "strip-ansi" ];
  };
  paths = lib.concatLists (lib.mapAttrsToList
    (pkg: bins: map (bin: { inherit pkg bin; path = ".config/bin/${bin}"; }) bins)
    placed);
in
{
  home.file = lib.listToAttrs (map
    (p: lib.nameValuePair p.path { source = "${ari.${p.pkg}}/bin/${p.bin}"; })
    paths);
  dotfiles.bridge.skip = map (p: p.path) paths;
}
