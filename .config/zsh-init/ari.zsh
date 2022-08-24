source_file "$HOME/.config/macos.sh"
source_file "$HOME/.config/aliases.sh"

# Add .config/bin to front of path
prepend_to_path "$HOME/.config/bin"

# Use nvim by default
export EDITOR="nvim"
alias vim='nvim'
alias vi='nvim'

# Let me use Ctrl-A / Ctrl-E as expected, even though $EDITOR is nvim
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

