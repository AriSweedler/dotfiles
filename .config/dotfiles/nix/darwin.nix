# System layer every machine gets. nix-darwin manages the Nix install itself (nix.enable).
{ user, ... }:
{
  nix.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";

  system.stateVersion = 6;
}
