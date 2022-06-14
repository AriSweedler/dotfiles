source_file "$HOME/.config/macos.sh"
source_file "$HOME/.config/aliases.sh"

# Add .config/bin to front of path
export PATH="$HOME/.config/bin:$PATH"

# Use vim by default
export EDITOR="vim"

# Let me use Ctrl-A / Ctrl-E as expected, even though $EDITOR is vim
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

