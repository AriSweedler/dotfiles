# The local tier's assembly: on a machine moved onto the one local-dotfiles repo (a clone at
# ~/local-dotfiles), every switch runs ldf-link, which links ~/.local's files to local/<machine> and
# the directories of the machine's tags. A machine without the clone is left alone (its tier is
# still the bare repo with ~/.local as its work tree). The script is the clone's linked bin, read
# at activation, so no flake needs the private repo as an input.
#
# A conflict or a refused file (ldf-link exit 1) is reported, not fatal: the switch still
# activates, and the next `ldf-link` names what to settle.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  path = lib.makeBinPath [ pkgs.zsh pkgs.git pkgs.coreutils pkgs.findutils pkgs.diffutils pkgs.gnused pkgs.hostname ];
in
{
  home.activation.ldfLink = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -d "${home}/local-dotfiles/.git" ]; then
      PATH="${path}:$PATH" run zsh "${home}/dotfiles/.config/bin/ldf-link" --execute \
        || echo "ldf-link: ~/.local not fully assembled; run ldf-link to see what to settle" >&2
    fi
  '';
}
