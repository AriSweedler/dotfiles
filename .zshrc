function source_file() {
  local -r file="$1"

  # shellcheck disable=SC1090
  [[ -r "$file" ]] && source "$file"
}

function source_zsh_dir() {
  local -r dir="$1"
  if [ ! -d "$dir" ]; then
    log_err "'$dir' is not a directory"
    return 1
  fi

  for file in $(find "$dir" -name "*.zsh"); do
    source_file "$file"
  done
}

# Source all files in these folders
source_zsh_dir "$HOME/.config/zsh-init"
source_zsh_dir "$HOME/.local/zsh-init"
