# 1) Load the 'compinit' function into the shell
autoload -U compinit

# 2) Use 'zstyle' to set some nice config options

# When there's not enough space to list all the completion options on one
# screen, we print a prompt telling the user that there's a long list.
#
# * %p is how far along we are. TOP, 40%, 80%, etc.
# * '%S' and '%s' start and end 'Standout' styling respectively
zstyle ':completion:*' list-prompt '%SHi Ari :), lots of options! At %p.%s'

# Allow for case-insensitive matches
zstyle ':completion:*' matcher-list 'm:{[:lower:]}={[:upper:]} r:|[._-]=** r:|=**'

# Treat multiple consecutive slashes as a single slash
zstyle ':completion:*' squeeze-slashes true

# Highlight the background of the selected item in the menu light blue
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors 'ma=30;46'  # Black text on cyan background

# 3) Tell the completion subsystem to use the following files
ZCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "${ZCACHE}"
zstyle ':completion:*' cache-path "${ZCACHE}/zcompcache"
compinit -d "${ZCACHE}/zcompdump-$ZSH_VERSION"
unset ZCACHE

# 4) Initialize the tab completion subsystem
compinit
# autoload -U +X bashcompinit && bashcompinit

# 5) Register my autoloadable functions and completions (ZDOTDIR)
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

# 6) Register my autoloadable functions and completions (local)
local_functions="$XDG_DATA_HOME/zsh/functions"
if [ -d "${local_functions}" ]; then
  fpath=("${local_functions}" $fpath)
  while IFS= read -r fxn; do
    autoload -z "$fxn"
  done < <(find "${local_functions}" -type f -exec basename {} \;)
fi

local_completions="$XDG_DATA_HOME/zsh/completions"
if [ -d "${local_completions}" ]; then
  fpath=("${local_completions}" $fpath)
  while IFS= read -r comp_fxn; do
    autoload -z "$comp_fxn"
    compdef "$comp_fxn" "${comp_fxn#_}"
  done < <(find "${local_completions}" -type f -exec basename {} \;)
fi

# Configure tab completions
setopt MENU_COMPLETE    # Immediately insert first match, TAB cycles
setopt AUTO_MENU        # Show menu on second TAB
unsetopt BEEP           # No bell

# Load menu selection module (creates menuselect keymap)
zmodload zsh/complist

# Cancel
bindkey -M menuselect '^E' send-break  # Cancel (like Vim)
bindkey -M menuselect '^[' send-break  # ESC also cancels
