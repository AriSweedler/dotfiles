#!/bin/sh
# Fresh Mac to the dotfiles baseline in one line (README "New machine"):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/AriSweedler/dotfiles/main/.config/new-machine/bin/bootstrap.sh)"
# POSIX sh because nothing from the dotfiles exists yet. Does only what `new-machine setup`
# cannot do for itself: a working git and the checkout that contains new-machine. Homebrew,
# packages, hooks and launchd are new-machine's steps, so re-running this is safe.
set -eu
GIT_DIR="$HOME/dotfiles.git"

[ "$(uname -s)" = Darwin ] || { echo "bootstrap: macOS only" >&2; exit 1; }

# /usr/bin/git is a stub until the Command Line Tools exist; --install is a GUI dialog.
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || :
  echo "bootstrap: click Install in the Command Line Tools dialog; waiting (Ctrl-C aborts)" >&2
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

# Fetch over https (no key yet), push over ssh once this machine's key is on GitHub; the
# tracking config is what lets a bare `git df push` work.
[ -d "$GIT_DIR" ] || git clone --bare --config remote.origin.pushurl=git@github.com:AriSweedler/dotfiles.git \
  --config branch.main.remote=origin --config branch.main.merge=refs/heads/main \
  "${DOTFILES_REMOTE:-https://github.com/AriSweedler/dotfiles.git}" "$GIT_DIR"

# A no-op once HOME is populated (its branch chatter to stderr); refuses, listing them, to overwrite files it does not own.
git --git-dir="$GIT_DIR" --work-tree="$HOME" checkout 1>&2

# The checkout carries the dotfiles harness; it finishes the dotfiles. Its output goes to stderr so --json's stdout stays new-machine's JSON.
zsh "$HOME/.config/bin/dotfiles" init 1>&2
exec "$HOME/.config/new-machine/bin/new-machine" setup "$@"
