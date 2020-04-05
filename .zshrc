files=()
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block, everything else may go below.
# System-level powerlevel10k stuff
files+="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
files+="$HOME/.p10k.zsh"
files+="$HOME/powerlevel10k/powerlevel10k.zsh-theme"
files+="$HOME/.fzf.zsh"
files+="$HOME/.aliases"

for file in $files; do
  [[ ! -r $file ]] || source $file
done

# Function to print a colormap
function colors() {
for i in {0..255}; do
  print -Pn "%K{$i} %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%8)):#7}:+$'\n'}
done
}

# When using !! or !$, command is redisplayed ready to run instead of ran
setopt histverify

# Use vim by default
export EDITOR=vim

# Let me use Ctrl-A / Ctrl-E as expected, even though $EDITOR is vim
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

# Add .local/bin to front of path
export PATH="$HOME/.local/bin:$PATH"
