# Classic
function double_cd() {
  # First arg is an absolute dir
  local target="$1"
  cd "$target" || return 1
  shift

  # Use next argument to filter down what we can use
  if [ -n "$1" ]; then
    local my_dirs=( $( find . -maxdepth 1 -type d -name "*$1*") )
    shift

    # Depending on how many folders we found with this filter, we may want to
    # let the user use fzf
    case "${#my_dirs[@]}" in
      0) :;;
      1) target="$my_dirs" ;;
      2)
        local fzf_args=(--select-1)
        if [ -n "$1" ]; then
          fzf_args+=(--query "$1")
        fi
        target="$(printf '%s\n' "${my_dirs[@]}" | fzf "${fzf_args[@]}")"
        ;;
    esac
  fi

  # Do  work and dump output
  cd "$target" || return 2
  b_echo "$(pwd)"
  ls -G

  # Rename the tmux window. Provide a default and allow user to override it
  local caller="${funcstack[2]}"
  if [ -n "$TMUX" ]; then
    if type -f "$caller::tmux_rename" &> /dev/null; then
      "$caller::tmux_rename" "$target"
    else
      tmux rename-window "${caller#c}"
    fi
  fi
}

# cd to my Desktop
function cdesk() {
  double_cd "$HOME/Desktop" "$@"
}

# cd to my Downloads folder
function cdown() {
  double_cd "$HOME/Downloads" "$@"
}
