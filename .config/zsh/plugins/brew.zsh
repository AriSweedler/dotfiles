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

  # Prepend brew completion files to the 'fpath'
  fpath=("${prefix}/share/zsh/site-functions" $fpath)
fi

unset prefix
unset brew_prefix

# TODO: This is what I want to configure
#
#    ==> Auto-updating Homebrew...
#     Adjust how often this is run with HOMEBREW_AUTO_UPDATE_SECS or disable with
#     HOMEBREW_NO_AUTO_UPDATE. Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
# 
#    ==> `brew cleanup` has not been run in the last 30 days, running now...
#     Disable this behaviour by setting HOMEBREW_NO_INSTALL_CLEANUP.
#     Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
#
# I don't want to have it update at the start. Update at the END. Ugh.
