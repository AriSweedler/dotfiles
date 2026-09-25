# step brew_pkgs — every declared item installed. The brew model (cmd/brew/brew.zsh) owns the
# verdict; `brew` in --tools means the runner reports a missing brew before this body runs.
step::declare brew_pkgs --group brew --needs brew --tools brew \
  --desc "every item declared in the merged Brewfiles is installed (brew bundle check/install --no-upgrade)"

check::brew_pkgs() {
  need_lib "${DOTFILES_BREW_LIB}"
  brew::check_pkgs_verdict
}

apply::brew_pkgs() {
  need_lib "${DOTFILES_BREW_LIB}"
  brew::apply_pkgs
}
