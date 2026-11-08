# GitHub CLI: ~/.config/gh/config.yml, written by home-manager. `gh config set` cannot write it
# (the file is in the store): set the value here, then `dotfiles switch`. hosts.yml, where
# `gh auth login` keeps the accounts, stays gh's own file.
{ ... }:
{
  programs.gh = {
    enable = true;
    # Git keeps the osxkeychain helper from git's system config; gh does not add its own.
    gitCredentialHelper.enable = false;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      prefer_editor_prompt = "disabled";
      aliases.co = "pr checkout";
      color_labels = "disabled";
      accessible_colors = "disabled";
      accessible_prompter = "disabled";
      spinner = "enabled";
    };
  };
}
