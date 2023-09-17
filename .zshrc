function source_file() {
  local -r file="$1"

  # shellcheck disable=SC1090
  [[ -r "$file" ]] || return
  source "$file"
}

function source_file::timed() {
  local -r file="$1"

  local timer_s timer_e
  timer_s="$(gdate +'%s%N')"
  # shellcheck disable=SC1090
  [[ -r "$file" ]] || return
  source "$file"
  timer_e="$(gdate +'%s%N')"
  echo "$((timer_e-timer_s)) Loading | file='$file' elapsed=$((timer_e-timer_s))"
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

  for file in $(find "$dir" -name "*.sh"); do
    log::err "Not sourcing file '$file'"
  done
}

# An idempotent way to add a path to PATH
function prepend_to_path() {
  local -r add_me="$1"
  case ":${PATH}:" in
    *:"$add_me":*) ;;
    *) export PATH="$add_me:$PATH" ;;
  esac
}

# Source all files in these folders
source_zsh_dir "$HOME/.config/zsh-init"
source_zsh_dir "$HOME/.local/zsh-init"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/ari/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/ari/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/ari/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/ari/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

