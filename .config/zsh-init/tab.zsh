# Prepend brew completion files to the 'FPATH'
if type brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi

# Enable tab completion for git. And more!
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit
