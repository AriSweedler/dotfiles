# Shared tier of the Nix port: the nix-darwin and home-manager modules every machine imports.
# Never switched on its own; each machine's local flake (~/.local/share/dotfiles/nix) calls
# lib.darwinSystem with its own modules. Inputs are pinned here, in this flake's lock.
{
  description = "Ari's shared dotfiles: nix-darwin and home-manager modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager }: {
    darwinModules.default = ./darwin.nix;
    homeModules.default = ./home.nix;

    # One machine's system: the shared modules, then the local tier's on top.
    lib.darwinSystem = { user, modules ? [ ], homeModules ? [ ] }:
      nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user; };
        modules = [
          self.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${user}.imports = [ self.homeModules.default ] ++ homeModules;
          }
        ] ++ modules;
      };
  };
}
