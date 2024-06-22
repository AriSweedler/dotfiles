# The ZSH_COMPDUMP file stores a cached compiled version of all the shell
# completion functions. It just helps startup time. By default it is stored
# under ~/.zcompdump, but I think that's silly
readonly ZSH_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh"
mkdir -p "${ZSH_DATA_DIR}"
ZSH_COMPDUMP="${ZSH_DATA_DIR}/zcompdump"
HISTFILE="${ZSH_DATA_DIR}/history"

# Prepend brew completion files to the 'FPATH'
if type brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi

# Enable tab completion for git. And more!
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit
