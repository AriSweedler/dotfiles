# Classic
function double_cd() {
  cd "$1" || return 1
  shift

  [ -z "$1" ] && return
  local my_dirs=( $( find . -maxdepth 1 -type d -name "*$1*") )
  shift
  local target
  case "${#my_dirs[@]}" in
    0) :;;
    1) target="$my_dirs" ;;
    2)
      local fzf_args=()
      fzf_args+=(--select-1)
      if [ -n "$1" ]; then
        fzf_args+=(--query "$1")
      fi
      target="$(printf '%s\n' "${my_dirs[@]}" | fzf "${fzf_args[@]}")"
      ;;
  esac

  cd "$target" || return 2
  if which tmux &>/dev/null; then
    local func="${funcstack[2]}"
    local btarget="$(basename "$target")"
    local sep=" "
    if [ "$func" = "cc" ]; then
      func=""
    fi
    if [ -z "$func" ] || [ -z "$btarget" ]; then
      sep=""
    fi
    tmux rename-window "${func}${sep}${btarget}"
  fi
  b_echo "$(pwd)"
  ls -G
}

# cd to my Desktop
function cdesk() {
  double_cd "$HOME/Desktop" "$1"
}

# cd to my Downloads folder
function cdown() {
  double_cd "$HOME/Downloads" "$1"
}

