# Set PS1 to something fancy. Starship reads ~/.config/starship.toml, which home-manager writes
# from ~/.config/dotfiles/nix/starship.nix; a local flake adds its own tables there.

# A shell started before the switch exported the old joined file's path; children inherit it.
unset STARSHIP_CONFIG
eval "$(starship init zsh)"
