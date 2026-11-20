# The personal tier: home-manager config for Ari's personal machines, and for no work machine.
# It lives in this shared repo, so it is public, but it is not global: the shared home module
# never imports it. A personal machine's own flake opts in by adding
# `dotfiles.homeModules.personal` to its homeModules (ozone: ~/.local/share/dotfiles/nix/flake.nix;
# co2: hosts/co2 in the homelab); a work machine leaves it out and gets none of this.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  # The clone's copy, as the bridge (../bridge.nix) links every shared file: edits are live.
  claudeSettings = "${home}/dotfiles/.config/dotfiles/nix/personal/claude-settings.json";
in
{
  # Claude Code's user settings. Linked out of store, so Claude Code's own writes (an approved
  # permission, /config) land in the tracked file and show up as a diff in the shared clone.
  # Hook commands say $HOME, not a home path, so the one file serves macOS and NixOS alike.
  home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink claudeSettings;

  # The model is each machine's choice, never the tier's: /model writes the key into the tracked
  # file, and this clean filter (named in ./.gitattributes) drops it from what git reads. A
  # checkout that rewrites the file drops the key from the working copy too: run /model again.
  programs.git.settings.filter.claude-settings.clean = "${pkgs.jq}/bin/jq 'del(.model)'";

  # The first switch on a machine finds Claude Code's own regular file where the link goes.
  # Remove it when it matches the tracked copy; a file that differs is left for home-manager to
  # back up as settings.json.before-nix.
  home.activation.claudeSettingsAdopt = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    f="${home}/.claude/settings.json"
    if [[ -f "$f" && ! -L "$f" ]] && cmp -s "$f" "${claudeSettings}"; then
      run rm "$f"
    fi
  '';
}
