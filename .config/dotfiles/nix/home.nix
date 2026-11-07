# User layer every machine gets: packages and the files home-manager places.
{ pkgs, ... }:
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
    git
    poppler-utils # pdftotext: the astound function parses invoices with it
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
    terminal-notifier # the Claude Code notification hook and git-health
    tmux # the same 3.8 brew had, so a server brew started still talks to this client
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
