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

# Ctrl+_ to undo (built-in)
# Ctrl+X Ctrl+_ to redo
bindkey '^X^_' redo

# Easily edit my machine's setup script. This script makes sure I have
# everything I expect on a machine. I have to update it if I install new
# permanent applications (language servers, command-line utilities, apps via
# brew, etc.)
function vnew() {
  vi "${HOME}/.config/new-machine.sh"
}
