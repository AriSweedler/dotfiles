function p10k::main() {
  if [ -f "$HOME/.config/zsh-init/starship.zsh" ]; then
    # Don't use p10k to set up our if we have starship to set up our prompts
    return
  fi

  # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
  # Initialization code that may require console input (password prompts, [y/n]
  # confirmations, etc.) must go above this block, everything else may go below.
  # System-level powerlevel10k stuff
  source_file "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
  source_file "$HOME/.p10k.zsh"
  source_file "$HOME/powerlevel10k/powerlevel10k.zsh-theme"

  source_file "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
}
p10k::main
