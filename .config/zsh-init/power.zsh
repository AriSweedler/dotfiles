# Functions that give me a bit more power

# Easier viewing of json files
alias jvim='vim -c "%!python3 -m json.tool" -c "set ft=json" -c "set foldmethod=syntax"'

# Start a webserver no matter the version of python. Used to be an alias:
# alias www='python -m SimpleHTTPServer 8000'
# But I want it to work for any version of python installed
function www() {
  local port="${1:-8000}"
  local python="python3"
  local module="http.server"
  if ! which python3; then
    # Everything else, which should be version 2
    python="python"
    module="SimpleHTTPServer"
  fi

  # Invoke the command
  "$python" -m "$module" "$port"
}

function key() {
  echo "pubkey copied to clipboard"
  pbcopy < "$HOME/.ssh/id_rsa.pub"
}

function scoop_downloads() {
  local -r download_dir="$HOME/Downloads"
  echo "Moving all files from '$download_dir' to pwd"
  local -r dir="downloads"
  mkdir -p "$dir"
  mv "$download_dir"/* "$dir"
  printf "\n%s:\n" "$dir"
  ls "$dir"
}

# Helper function to let you know how many args there are. Useful for when
# you're messing with arrays and unquoted variable expansion as arguments
function describe() {
  echo "There are '$#' args:"
  while (( $# > 0 )); do
    echo "arg: '$1'"
    shift
  done
  echo
}
