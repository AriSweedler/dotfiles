# User layer every machine gets: packages and the files home-manager places.
{ pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = [ pkgs.nix-tree pkgs.nvd ];

  # Marker that a home-manager generation is live; the dotfiles healthcheck can read it.
  home.file.".local/state/dotfiles/nix-managed".text = "placed by home-manager from ~/.config/dotfiles/nix\n";
}
