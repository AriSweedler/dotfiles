# source_file "$HOME/.config/macos.sh"

# Add .config/bin to front of path
prepend_to_path "$HOME/.config/bin"

# Use nvim by default
export EDITOR="nvim"
alias vi='nvim'
alias vim='nvim'
alias vimdiff='nvim -d'

# Enable colors by default in ls
alias ls='ls -G'

# What's the magic word
alias please=sudo

# Explicitly use 'vi' mode for 'zle', even though we are already here because
# of setting '$EDITOR=nvim'.
bindkey -v

# zle - https://thevaluable.dev/zsh-line-editor-configuration-mouseless/
bindkey "^A" vi-beginning-of-line
bindkey "^B" vi-beginning-of-line
bindkey "^E" vi-end-of-line

# Bash has this by default, I want it too.
autoload edit-command-line
zle -N edit-command-line
bindkey "^X^E" edit-command-line

# Run a command DIRECTLY from a keystroke:
# https://unix.stackexchange.com/a/668986/248906
function ari-keystroke-coder { cc; zle redisplay; }
zle -N ari-keystroke-coder
bindkey '^o' ari-keystroke-coder
