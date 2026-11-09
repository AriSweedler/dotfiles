# User layer every machine gets: packages and the files home-manager places.
{ pkgs, src, ... }:
let
  # Neovim pinned to the exact commit Ari ran under bob (v0.13.0-dev-853+g7945732ed7, 2026-06-29),
  # built with nixpkgs' recipe. The version moves only when rev and hash are edited here; a
  # nixpkgs update never bumps it. The source tarball has no .git, so `nvim --version` prints
  # v0.13.0-dev without the commit suffix.
  neovim-pinned = pkgs.neovim-unwrapped.overrideAttrs (_: {
    version = "0.13.0-dev";
    src = pkgs.fetchFromGitHub {
      owner = "neovim";
      repo = "neovim";
      rev = "7945732ed7bb211f91112292a13b51fc3182599b";
      hash = "sha256-DrGUyUf93fzovmHmMDUKfYERkrtA/+laGhQCOWEtnTw=";
    };
  });
in
{
  # Tools configured as modules rather than linked files: their config is in the store.
  imports = [ ./claude-skills.nix ./gh.nix ./git.nix ./karabiner.nix ./nvim.nix ./starship.nix ./tmux.nix ./raycast-snippets.nix ./tmux-oneshot.nix ./tmuxinator.nix ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # Unix essentials
    # brew's "awk": the one true awk, second edition (UTF-8 aware). nixpkgs installs it only as
    # nawk, and macOS's /usr/bin/awk (2020, counts bytes) would answer to `awk` instead.
    (runCommand "awk" { } ''
      mkdir -p $out/bin
      ln -s ${nawk}/bin/nawk $out/bin/awk
      ln -s ${nawk}/bin/nawk $out/bin/nawk
    '')
    coreutils-prefixed # g-prefixed, as brew installs it, so BSD ls and friends stay first
    curl
    poppler-utils # pdftotext: the astound function parses invoices with it
    watch
    wget

    # Nicer CLI
    bat
    delta # git's pager (git.nix)
    fd
    fzf
    gum # shell UI: the dotfiles harness's spinners and boxes
    jq
    mas # Mac App Store from the terminal: mas install 497799835 is Xcode (alttab builds with it)
    ripgrep
    terminal-notifier # the Claude Code notification hook and git-health
    tmuxinator
    tree
    yq-go

    # Shells. /bin/bash is 3.2; the local-dotfiles pre-commit hook needs bash 5 (mapfile).
    bashInteractive
    zsh

    # Editor
    neovim-pinned

    # Lang: misc
    lua
    lua-language-server
    shellcheck

    # Ari's own tools, built from their submodules
    (callPackage ./pkgs/plugged { inherit src; })

    # Apps: home-manager copies them into ~/Applications/Home Manager Apps
    monitorcontrol # brightness and volume keys for external displays

    # Nix
    nix-tree
    nvd
  ];

  # zsh/plugins/zsh-vi-mode.zsh sources the plugin from here: the profile links only some of
  # share/, never share/zsh-vi-mode.
  home.file.".local/share/zsh-vi-mode".source = "${pkgs.zsh-vi-mode}/share/zsh-vi-mode";

  # Marker that a home-manager generation is live; the dotfiles healthcheck can read it.
  home.file.".local/state/dotfiles/nix-managed".text = "placed by home-manager from ~/.config/dotfiles/nix\n";
}
