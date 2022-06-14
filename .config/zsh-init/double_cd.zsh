# Classic
function double_cd() {
  if [ -z "$2" ]; then
    cd "$1" || return 1
    return
  fi

  cd "$1"/*"$2"* || cd "$1" || return 2
  b_echo "$(pwd)"
  ls
}

function ensure_dir_created() {
  test -d "$1" && return
  echo "Creating dir '$1'"
  mkdir -p "$1"
}

