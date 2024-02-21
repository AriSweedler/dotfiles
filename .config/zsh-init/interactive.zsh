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
