# 1) Load the 'compinit' function into the shell
autoload -U compinit

# 2) Use 'zstyle' to set some nice config options

# When there's not enough space to list all the completion options on one
# screen, we print a prompt telling the user that there's a long list.
#
# * %p is how far along we are. TOP, 40%, 80%, etc.
# * '%S' and '%s' start and end 'Standout' styling respectively
zstyle ':completion:*' list-prompt '%SHi Ari :), lots of options! At %p.%s'

# Use default colors when we're listing completion options
zstyle ':completion:*' list-colors ''

# Allow for case-insensitive matches
zstyle ':completion:*' matcher-list 'm:{[:lower:]}={[:upper:]} r:|[._-]=** r:|=**'

# Treat multiple consecutive slashes as a single slash
zstyle ':completion:*' squeeze-slashes true

# 3) Tell the completion subsystem to use the following files
ZCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "${ZCACHE}"
zstyle ':completion:*' cache-path "${ZCACHE}/zcompcache"
compinit -d "${ZCACHE}/zcompdump-$ZSH_VERSION"
unset ZCACHE

# 4) Initialize the tab completion subsystem
compinit
# autoload -U +X bashcompinit && bashcompinit

# 5) Register my autoloadable functions and completions
fpath=("$ZDOTDIR/functions" $fpath)
while IFS= read -r fxn; do
  autoload -z "$fxn"
done < <(find "${ZDOTDIR}/functions" -type f -exec basename {} \;)

fpath=("$ZDOTDIR/completions" $fpath)
while IFS= read -r comp_fxn; do
  autoload -z "$comp_fxn"
  if [ -x "$comp_fxn" ]; then
    log::warn "Completion function is not executable | comp_fxn='$comp_fxn'"
    continue
  fi
  compdef "$comp_fxn" "${comp_fxn#_}"
done < <(find "${ZDOTDIR}/completions" -type f -exec basename {} \;)
