export SHELL_SESSIONS_DISABLE=1
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

# XDG best practices:
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# XDG_DATA_DIRS
# If $XDG_DATA_DIRS is either not set or empty, a value equal to /usr/local/share/:/usr/share/ should be used.
#
# XDG_CONFIG_DIRS
# If $XDG_CONFIG_DIRS is either not set or empty, a value equal to /etc/xdg should be used.

# macOS /etc/zshrc disables zsh's `log` builtin for interactive shells. But
# non-interactive shells (e.g. spawned by claude) to not get the same benefits.
# This is useful for when claude wants to read system logs (debugging when stuff
# has been plugged into USB ports)
disable log
