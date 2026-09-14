# source_file "$HOME/.config/macos.sh"

# PATH policy for both dotfile tiers: shared bins, then this machine's local bins.
prepend_to_path "$HOME/.config/bin"
prepend_to_path "$HOME/.local/bin"
prepend_to_path "$XDG_DATA_HOME/bin"

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

# Edit the shared new-machine Brewfile: everything every machine gets. Applied by
# `new-machine setup` together with ~/.local/share/new-machine/Brewfile (this
# machine only). Add lines with `new-machine brew decree <name> --global|--local`.
function vi_::new_machine_brewfile() {
  "${EDITOR}" "${HOME}/.config/new-machine/Brewfile"
}
alias vi_newmachbrew=vi_::new_machine_brewfile

alias pbl=pbpastelinks
