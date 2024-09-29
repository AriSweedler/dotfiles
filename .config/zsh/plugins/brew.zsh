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

# Because I ran:
#
#     brew tap homebrew/autoupdate
#     brew autoupdate start
#
# I can do this
HOMEBREW_NO_AUTO_UPDATE=true
