# This machine's identity, set once in the local tier (~/.local/share/dotfiles/nix/home.nix) and
# read by every module that shows it: starship.nix (the prompt's ssh symbol) and tmux.nix (the
# status line's @machine-symbol). Unset, nothing changes.
{ lib, ... }:
{
  options.dotfiles.machine.symbol = lib.mkOption {
    type = lib.types.str;
    default = "";
    example = "🏠";
    description = "This machine's symbol in the prompt and the tmux status line; empty shows none.";
  };
}
