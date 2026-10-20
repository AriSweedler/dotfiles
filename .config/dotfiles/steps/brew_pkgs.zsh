# step brew_pkgs — every declared item installed. The brew model (cmd/brew/brew.zsh) owns the
# verdict; `brew` in --tools means the runner reports a missing brew before this body runs.
step::declare brew_pkgs --group brew --needs brew --tools brew \
  --desc "every item declared in the merged Brewfiles is installed (brew bundle check/install --no-upgrade)" \
  --apply "installs every missing item of the merged Brewfiles (brew bundle install --no-upgrade)"
step::watches brew_pkgs '.config/new-machine/Brewfile'

check::brew_pkgs() {
  need_lib "${ARI_DOTFILES_BREW_LIB}"
  # Cached on everything the brew model reads (cache.zsh). A busy brew that has changed nothing
  # yet leaves the stored verdict true; once it touches a keg, the miss runs the busy check.
  local -a reply inputs
  if ! cache::brew_tier_inputs; then brew::check_pkgs_verdict; return 0; fi
  inputs=("${reply[@]}")
  if ! cache::brew_inputs; then brew::check_pkgs_verdict; return 0; fi
  cache::check brew::check_pkgs_verdict "${inputs[@]}" "${reply[@]}"
}

apply::brew_pkgs() {
  need_lib "${ARI_DOTFILES_BREW_LIB}"
  brew::apply_pkgs
}
