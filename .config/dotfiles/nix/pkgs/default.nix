# Ari's own packages, one attribute each: the shared flake exports them as packages.<system>.*
# and home.nix installs them. src is the repo root (the flake's source).
{ pkgs, src }:
{
  ari_zshlib = pkgs.callPackage ./ari-zshlib { inherit src; };
  plugged = pkgs.callPackage ./plugged { inherit src; };
}
