# XDG best practices:
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"

# XDG_DATA_DIRS
# If $XDG_DATA_DIRS is either not set or empty, a value equal to /usr/local/share/:/usr/share/ should be used.
#
# XDG_CONFIG_DIRS
# If $XDG_CONFIG_DIRS is either not set or empty, a value equal to /etc/xdg should be used.
#
# XDG_CACHE_HOME
# If $XDG_CACHE_HOME is either not set or empty, a default equal to $HOME/.cache should be used.
