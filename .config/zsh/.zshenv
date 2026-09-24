# Read by every zsh that starts with ZDOTDIR already exported (children of a configured
# shell, `zsh -c`, scripts, the shells Claude spawns); ~/.zshenv sources it too, so the
# root login shell gets the same lines. Keep it to what every shell needs before .zshrc.

# macOS /etc/zshrc disables zsh's `log` builtin, but only for interactive shells. Without
# this, `log show` in a script or a `zsh -c` hits the builtin and dies with
# "too many arguments" instead of reaching /usr/bin/log.
disable log
