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
