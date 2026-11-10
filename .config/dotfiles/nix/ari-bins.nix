# Ari's packaged bins, placed where the clone's copies were linked: ~/.config/bin/<name> (and
# ~/.config/git/bin/git-dotfiles) now point into the store, so every caller that names that path
# (/ari-driving, git's df alias, a remote host's run_log) keeps working, and the bridge skips the
# clone's file. An edit to one reaches HOME at the next `dotfiles switch` (package what you run,
# link what you edit).
{ lib, pkgs, src, ... }:
let
  ari = import ./pkgs { inherit pkgs src; };
  # package → the repo paths of its bins; each is placed at that path under HOME, from the
  # package's bin/<basename>.
  placed = {
    run-log = map (b: ".config/bin/${b}") [ "run_log" "run_log-capture.py" "irun" "strip-ansi" ];
    git-kit = [ ".config/git/bin/git-dotfiles" ] ++ map (b: ".config/bin/${b}") [
      "git-health" "git-ready" "git-delete-if-merged-all" "git-delete-if-merged-one" "git-dedupe-case-refs" "repo"
    ];
    notes = [ ".config/bin/notes" ];
    mac-utils = map (b: ".config/bin/${b}") [
      "applelink" "applepaste" "chrome-headless" "favicon-maker" "json-sort" "karabiner-list-keyboards" "notif-center"
      "open-any" "open-link" "pbpastelinks" "probe-color" "probe-emoji" "replace" "utc-date" "yubitap"
    ];
  };
  paths = lib.concatLists (lib.mapAttrsToList
    (pkg: rels: map (path: { inherit pkg path; bin = baseNameOf path; }) rels)
    placed);
in
{
  home.file = lib.listToAttrs (map
    (p: lib.nameValuePair p.path { source = "${ari.${p.pkg}}/bin/${p.bin}"; })
    paths);
  dotfiles.bridge.skip = map (p: p.path) paths;
}
