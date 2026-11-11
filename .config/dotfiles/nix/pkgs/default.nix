# Ari's own packages, one attribute each: the shared flake exports them as packages.<system>.*
# and home.nix installs them. src is the repo root (the flake's source); devInputs the dev repos'
# flake inputs (../dev-repos).
{ pkgs, src, devInputs }:
let
  self = {
    ari_zshlib = pkgs.callPackage ./ari-zshlib { inherit src; };
    plugged = pkgs.callPackage ./plugged { src = devInputs.plugged; };
    # The run-log dev repo's own recipe, given this tree's library.
    run-log = pkgs.callPackage "${devInputs.run-log}/package.nix" { zshlib = self.ari_zshlib; };
    git-kit = pkgs.callPackage ./git-kit { inherit src; inherit (self) ari_zshlib; };
    notes = pkgs.callPackage ./notes { inherit src; inherit (self) ari_zshlib; };
    mac-utils = pkgs.callPackage ./mac-utils { inherit src; inherit (self) ari_zshlib; };
    dotfiles-cli = pkgs.callPackage ./dotfiles-cli { inherit src; };
  };
in
self
