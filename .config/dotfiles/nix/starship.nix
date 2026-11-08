# Starship prompt: ~/.config/starship.toml, written by home-manager from these settings. A local
# flake adds its own tables to programs.starship.settings; the module system merges them, and a
# key set in both tiers fails the build. An edit takes effect at the next `dotfiles switch`.
# zsh/plugins/starship.zsh runs `starship init`.
{ ... }:
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
    };
  };
}
