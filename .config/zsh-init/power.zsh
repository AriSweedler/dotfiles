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

# Shell lib function
function wait_for_keypress() {
  echo -n "Press any key to continue..."

  (
    # Turn off printing to the screen while this scope is active (so 'read -k1'
    # doesn't echo user input)
    stty -echo
    trap 'stty echo' EXIT
    read -k1
  )

  # Move the cursor to the start of the line and clear the rest.
  #
  # TODO it would be better if we restored position to what it was at the start
  # of this function instead of just assuming we started at the start of a line
  printf "\r\033[K"
}

function clipboard() {
  # Parse args
  local -r value="${1:?}"
  shift 1
  local descr
  while (( $# > 0 )); do
    case "$1" in
      --description) descr="Placing value on clipboard: $2"; shift 2 || break ;;
      *) log::err "Unkonwn argument in ${FUNCNAME[0]}: '$1'"; exit 1 ;;
    esac
  done

  # Massage args
  if [ -z "$descr" ]; then
    descr="Placing value on clipboard"
  fi

  # Do work
  log::info "$description | value='$value'"
  echo -n "$value" | pbcopy
}

