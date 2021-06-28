# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.

# Source these files
files=()
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block, everything else may go below.
# System-level powerlevel10k stuff
files+="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
files+="$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
files+="$HOME/.p10k.zsh"
files+="$HOME/powerlevel10k/powerlevel10k.zsh-theme"
files+="$HOME/.fzf.zsh"
files+="$HOME/.macos"
files+="$HOME/.aliases"
files+="$HOME/.local/this-computer.zsh"
for file in $files; do
  [[ ! -r $file ]] || source $file
done

# Add .local/bin to front of path
export PATH="$HOME/.local/bin:$PATH"

# Enable tab completion for git. And more!
autoload -Uz compinit && compinit

# Set history stuff. https://zsh.sourceforge.io/Doc/Release/Options.html#History
setopt SHARE_HISTORY          # imports new commands from the history file, and also causes your typed commands to be appended to the history file immediately
setopt HIST_IGNORE_SPACE      # ignore commands that start with space
setopt HIST_EXPIRE_DUPS_FIRST # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt HIST_FCNTL_LOCK        # Use a more modern way to lock the history file. Should be a net positive on my shiny new machine
setopt EXTENDED_HISTORY       # Add timestamps to history files
setopt HIST_REDUCE_BLANKS     # Trim silly whitespace from history
setopt HISTVERIFY             # When using !! or !$, command is redisplayed ready to run instead of ran
export HISTFILE="$HOME/.histfile"
export HISTSIZE=1000
export SAVEHIST=$HISTSIZE

# Use vim by default
export EDITOR="vim"

# Let me use Ctrl-A / Ctrl-E as expected, even though $EDITOR is vim
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

#################################### XDG ################################### {{{
# XDG best practices:
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
############################################################################ }}}

# The following lines were added by compinstall
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list 'm:{[:lower:]}={[:upper:]} r:|[._-]=** r:|=**'
zstyle ':completion:*' squeeze-slashes true
zstyle :compinstall filename '/Users/arisweedler/.zshrc'

# Fun little function to print a colormap
function colors() {
  for i in {0..255}; do
    print -Pn "%K{$i} %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%8)):#7}:+$'\n'}
  done
}
