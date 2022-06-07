# XDG best practices:
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# If $XDG_DATA_HOME is either not set or empty, a default equal to
# $HOME/.local/share should be used
export XDG_DATA_HOME="$HOME/.local"

#If $XDG_CONFIG_HOME is either not set or empty, a default equal to
# $HOME/.config should be used
export XDG_CONFIG_HOME="$HOME/.config"

# XDG_DATA_DIRS
# If $XDG_CONFIG_HOME is either not set or empty, a default equal to $HOME/.config should be used
#
# XDG_CONFIG_DIRS
# If $XDG_CONFIG_DIRS is either not set or empty, a value equal to /etc/xdg should be used.
#
# XDG_CACHE_HOME
# If $XDG_CACHE_HOME is either not set or empty, a default equal to $HOME/.cache should be used.
#
# XDG_CACHE_HOME
