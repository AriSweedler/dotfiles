# Starship prompt: ~/.config/starship.toml, written by home-manager from these settings. A local
# flake adds its own tables to programs.starship.settings; the module system merges them. A key
# the shared tier sets with lib.mkDefault, a local flake may set again and wins; a plain key set
# in both tiers fails the build. An edit takes effect at the next `dotfiles switch`.
# zsh/plugins/starship.zsh runs `starship init`.
{ config, lib, ... }:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = false; # home-manager does not manage zsh here
    settings = {
      nodejs.symbol = "[⬢](bold green) ";
      git_branch.symbol = " ";
      git_metrics.disabled = true;
      git_status = {
        style = "bg:black fg:bold green";
        disabled = true;
      };
      cmake.symbol = "cmake ";
      terraform.symbol = " ";
      battery.discharging_symbol = "⚡️ ";
      gcloud = {
        symbol = "󰊶 ";
        format = "[$symbol$active]($style) ";
      };
      time = {
        disabled = false;
        time_format = "%T UTC";
        utc_time_offset = "0";
      };
      # (N): this machine's unread notifications, which zsh/plugins/notify_badge.zsh exports
      # before each prompt, and leaves unset at 0.
      env_var.NOTIFY_UNREAD = {
        format = "[\\($env_value\\)]($style) ";
        style = "bold yellow";
      };
    }
    # The symbol over ssh, from dotfiles.machine.symbol (machine.nix); unset keeps Starship's own.
    // lib.optionalAttrs (config.dotfiles.machine.symbol != "") {
      hostname.ssh_symbol = lib.mkDefault "${config.dotfiles.machine.symbol} ";
    };
  };
}
