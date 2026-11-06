# step brew_drift — nothing installed on request is undeclared, orphaned or declared twice, and
# every Brewfile entry and ignore says why it is there. No apply: a human settles drift with
# `brew triage` / `brew decree`, and documents an entry with `brew edit`.
step::declare brew_drift --group brew --needs brew --tools brew \
  --desc "nothing installed on request is undeclared, orphaned, or declared twice; every entry says why (${CLI_NAME} brew triage)"
step::watches brew_drift '.config/new-machine/Brewfile' '.config/new-machine/Brewfile.ignore'

check::brew_drift() {
  # Under nix-darwin the flakes declare Homebrew and a switch applies it with cleanup =
  # uninstall, so the tier Brewfiles are no longer the declared state (/ari-dotfiles-nix).
  if [[ -r "${ARI_DOTFILES_NIX_BREWFILE}" ]]; then
    verdict skip nix_declared -d "the flakes declare Homebrew; a darwin-rebuild switch applies them | brewfile='${ARI_DOTFILES_NIX_BREWFILE}'"
    return 0
  fi
  need_lib "${ARI_DOTFILES_BREW_LIB}"
  # Cached on everything the brew model reads (cache.zsh). A busy brew that has changed nothing
  # yet leaves the stored verdict true; once it touches a keg, the miss runs the busy check.
  local -a reply inputs
  if ! cache::brew_tier_inputs; then brew::check_drift_verdict; return 0; fi
  inputs=("${reply[@]}")
  if ! cache::brew_inputs; then brew::check_drift_verdict; return 0; fi
  cache::check brew::check_drift_verdict "${inputs[@]}" "${reply[@]}"
}
