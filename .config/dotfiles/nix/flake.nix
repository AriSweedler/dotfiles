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
    # Ari's own repos (../dev-repos), read as plain sources. Each is checked out in the clone too;
    # `dotfiles switch` overrides the input with that checkout's HEAD, and `dotfiles push` bumps
    # this lock after pushing it.
    plugged = { url = "github:AriSweedler/plugged"; flake = false; };
    chrome-exoskeleton = { url = "github:AriSweedler/chrome-exoskeleton"; flake = false; };
    run-log = { url = "github:AriSweedler/run-log"; flake = false; };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, plugged, chrome-exoskeleton, run-log }:
  let devInputs = { inherit plugged chrome-exoskeleton run-log; };
  in {
    darwinModules.default = ./darwin.nix;
    homeModules.default = ./home.nix;

    # Ari's own packages (pkgs/default.nix): `nix build <this flake>#ari_zshlib`.
    packages.aarch64-darwin = import ./pkgs {
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      src = self.sourceInfo.outPath;
      inherit devInputs;
    };

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
            # The repo root for bridge.nix: the whole repo under a git+file input, only this
            # directory under a path: one.
            home-manager.extraSpecialArgs = { src = self.sourceInfo.outPath; inherit devInputs; };
            # A file in HOME where a link goes is moved aside, never overwritten: the first
            # switch after the clone, or a tool that replaced a link with a file of its own.
            home-manager.backupFileExtension = "before-nix";
            home-manager.users.${user}.imports = [ self.homeModules.default ./bridge.nix ] ++ homeModules;
          }
        ] ++ modules;
      };

    # The same user layer on a NixOS machine, as one module for its nixosSystem: the shared home
    # module and the bridge for `user`, whose clone is ~/dotfiles there too. The machine's own
    # flake owns the system; this adds only home-manager. Mac-only packages and bins stay out
    # (home.nix, ari-bins.nix).
    lib.nixosHome = { user, homeModules ? [ ] }: {
      imports = [ home-manager.nixosModules.home-manager ];
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { src = self.sourceInfo.outPath; inherit devInputs; };
      home-manager.backupFileExtension = "before-nix";
      home-manager.users.${user}.imports = [ self.homeModules.default ./bridge.nix ] ++ homeModules;
    };
  };
}
