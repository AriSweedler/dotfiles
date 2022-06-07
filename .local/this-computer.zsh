# Add to path
export PATH="$HOME/devenv/bin:$PATH"
export PATH="$HOME/devenv/groot/bin:$PATH"
export PATH="$PATH:/usr/local/bin"
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"

alias ls='ls -G --color'

# Source these files
for file in $(find "$HOME/.local/zsh-init" -name "*.zsh"); do
  # shellcheck disable=SC1090
  [[ ! -r "$file" ]] || source "$file"
done

# SSH stuff
export ssh_user=asweedler
for id_rsa in "$HOME"/.ssh/*id_rsa; do
  ssh-add "$id_rsa" 2&>/dev/null
done
