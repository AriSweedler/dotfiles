# tmux: ~/.config/tmux/tmux.conf, written by home-manager from the typed options below and then
# the tmux/*.conf files in order; typhon, the status-line and key-table plugin, loads last from
# the store. An edit takes effect at the next `dotfiles switch`, then <Prefix>C-s in a running
# server. A local flake appends its own lines with programs.tmux.extraConfig.
{ lib, pkgs, ... }:
let
  typhon = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "typhon";
    rtpFilePath = "typhon.tmux";
    version = "2026-09-10";
    src = pkgs.fetchFromGitHub {
      owner = "AriSweedler";
      repo = "tmux-typhon";
      rev = "193b5ad9d4cd403ca01141848d4b1dea8cef1dd7";
      hash = "sha256-rYaxpkEJ15z7RtS1JJI12Kh6r8G2AvANf6ZcJplA9OQ=";
    };
  };
  # A working copy of typhon here is loaded instead of the pinned one, to try a change before
  # bumping rev and hash above.
  typhonDev = "~/.local/share/tmux/local-plugins/tmux-typhon/typhon.tmux";
in
{
  programs.tmux = {
    enable = true;
    sensibleOnTop = false;
    prefix = "C-a";
    baseIndex = 1;
    terminal = "screen-256color";
    shell = if pkgs.stdenv.hostPlatform.isDarwin then "/bin/zsh" else "${pkgs.zsh}/bin/zsh"; # NixOS has no /bin/zsh
    keyMode = "vi"; # copy mode moves with vim keys
    mouse = true;
    focusEvents = true;
    clock24 = true; # tmux's own default
    historyLimit = 5000; # for long output, tee to a file and `less +F` it
    escapeTime = 0;
    extraConfig = ''
      # The server's shell commands (run-shell, if-shell, typhon) run with the PATH it was started
      # with, which can lack the Nix profiles: put them first, once.
      run-shell 'case ":$PATH:" in *:/etc/profiles/per-user/$USER/bin:*) ;; *) /etc/profiles/per-user/$USER/bin/tmux set-environment -g PATH "/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH" ;; esac'

      # <Prefix>C-s re-reads this file; <Prefix>C-e edits its source, which a switch applies
      bind-key C-s source-file "$XDG_CONFIG_HOME/tmux/tmux.conf" \; display-message "Sourced tmux.conf"
      bind-key C-e new-window -c ~/dotfiles/.config/dotfiles/nix \; send-keys "\$EDITOR tmux.nix" Enter

      ${builtins.concatStringsSep "\n" (map builtins.readFile [
        ./tmux/copy.conf
        ./tmux/f12.conf
        ./tmux/keybindings.conf
        ./tmux/macros.conf
        ./tmux/mouse.conf
        ./tmux/osc8-hyperlinks.conf
        ./tmux/prefix.conf
        ./tmux/resize-panes.conf
        ./tmux/settings.conf
        ./tmux/typhon.conf
      ])}
      ${lib.optionalString (!pkgs.stdenv.hostPlatform.isDarwin) ''

        # Clipboard history off a Mac, where Hyper+4 opens Raycast's: the keyboard remapper sends
        # <Prefix>M-4, and clip-hist (pkgs/linux-clipboard) pastes the pick into the pane it came from.
        bind-key M-4 run-shell "tmux display-popup -E -T ' clipboard ' -b rounded -w 80% -h 60% 'clip-hist --paste-to #{pane_id}'"
      ''}

      if-shell 'test -f ${typhonDev}' 'run-shell ${typhonDev}' 'run-shell ${typhon.rtp}'
    '';
  };

  # typhon.tmux reads key tables from ~/.config/tmux/typhon.d, its help.sh their help text.
  xdg.configFile."tmux/typhon.d".source = ./tmux/typhon.d;
  xdg.configFile."tmux/typhon-help".source = ./tmux/typhon-help;
}
