# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block, everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

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

################################################################################
###################################### XDG #####################################
# Big man thinks he can follow best practices:
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# If $XDG_DATA_HOME is either not set or empty, a default equal to
# $HOME/.local/share should be used
export XDG_DATA_HOME="$HOME/.local"

#If $XDG_CONFIG_HOME is either not set or empty, a default equal to
# $HOME/.config should be used
export XDG_CONFIG_HOME="$HOME/.config"

# XDG_DATA_DIRS
# If $XDG_CONFIG_HOME is either not set or empty, a default equal to $HOME/.config should be used
#
# XDG_CONFIG_DIRS
# If $XDG_CONFIG_DIRS is either not set or empty, a value equal to /etc/xdg should be used.
#
# XDG_CACHE_HOME
# If $XDG_CACHE_HOME is either not set or empty, a default equal to $HOME/.cache should be used.
#
# XDG_CACHE_HOME
################################################################################

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Syntax highlighting
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
