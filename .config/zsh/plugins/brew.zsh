# Check if we have 'brew' installed. Log a warning if not
#
# Can't use 'brew --prefix' lol
function brew_prefix() {
  for path in "/opt/homebrew" "/usr/local"; do
    [ -x "${path}/bin/brew" ] || continue
    echo "${path}"
    return
  done

  log::warn "You do not have 'brew' installed"
  return 1
}

if prefix="$(brew_prefix)"; then
  # Get homebrew set up (sets env variables, including PATH & MANPATH)
  eval "$("${prefix}/bin/brew" shellenv)"

  # Move the fpath prepending that 'brew shellenv' did - move it to the end
  local my_path="${prefix}/share/zsh/site-functions"
  fpath=(${fpath:#$my_path} ${my_path})
fi

unset prefix
unset brew_prefix

# Keep interactive brew commands fast: no self-update, no upgrading the dependents of whatever
# an install touches, no cleanup pass. Exported, or brew never sees them. Nothing refreshes
# Homebrew in the background (the Nix flakes declare what it holds): `brew update` by hand
# before declaring a formula that needs a newer index.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
