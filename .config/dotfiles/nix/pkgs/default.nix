# Ari's own packages, one attribute each: the shared flake exports them as packages.<system>.*
# and home.nix installs them. src is the repo root (the flake's source).
{ pkgs, src }:
let
  self = {
    ari_zshlib = pkgs.callPackage ./ari-zshlib { inherit src; };
    plugged = pkgs.callPackage ./plugged { inherit src; };
    run-log = pkgs.callPackage ./run-log { inherit src; inherit (self) ari_zshlib; };
    git-kit = pkgs.callPackage ./git-kit { inherit src; inherit (self) ari_zshlib; };
    notes = pkgs.callPackage ./notes { inherit src; inherit (self) ari_zshlib; };
    mac-utils = pkgs.callPackage ./mac-utils { inherit src; inherit (self) ari_zshlib; };
  };
in
self
