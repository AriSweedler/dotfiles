# User layer every machine gets: packages and the files home-manager places.
{ pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # Unix essentials
    nawk # brew's "awk": the one true awk
    coreutils-prefixed # g-prefixed, as brew installs it, so BSD ls and friends stay first
    curl
    git
    watch
    wget

    # Nicer CLI
    bat
    delta
    fd
    fzf
    gum # shell UI: the dotfiles harness's spinners and boxes
    jq
    mas # Mac App Store from the terminal: mas install 497799835 is Xcode (alttab builds with it)
    ripgrep
    starship # shell prompt
    tmuxinator
    tree
    yq-go

    # Shells. /bin/bash is 3.2; the local-dotfiles pre-commit hook needs bash 5 (mapfile).
    bashInteractive
    zsh

    # Lang: misc
    lua
    lua-language-server
    shellcheck

    # Nix
    nix-tree
    nvd
  ];

  # Marker that a home-manager generation is live; the dotfiles healthcheck can read it.
  home.file.".local/state/dotfiles/nix-managed".text = "placed by home-manager from ~/.config/dotfiles/nix\n";
}
