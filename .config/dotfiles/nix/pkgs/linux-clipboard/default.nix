# pbcopy, pbpaste and clip-hist for Linux (clipboard.sh has the design). Installed only off a
# Mac (home.nix): there the real pbcopy and Raycast do this.
{ writeShellApplication, symlinkJoin, coreutils, diffutils, findutils, fzf }:
let
  command = name: writeShellApplication {
    inherit name;
    # tmux comes from the caller's PATH: clip-hist must talk to the server it was run from.
    runtimeInputs = [ coreutils diffutils findutils fzf ];
    text = builtins.readFile ./clipboard.sh;
  };
in
symlinkJoin {
  name = "linux-clipboard-0";
  paths = map command [ "pbcopy" "pbpaste" "clip-hist" ];
}
