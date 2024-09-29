function color::contrast() {
  local r g b luminance
  color="$1"

  # In the first 16 - use white for '00' only
  if (( color < 16 )); then
    (( color == 0 )) && printf "15" || printf "0"
    return
  fi

  # In the greyscale (last 24) - use white for the first half
  if (( color > 231 )); then # Greyscale ramp
    (( color < 244 )) && printf "15" || printf "0"
    return
  fi

  # For each block of 36 colors - Use white for the first 3rd
  g=$(( ( (color-16) % 36) / 6 ))
  (( g < 2 )) && printf "15" || printf "0"
}

function color::ize() {
  # Read input
  local content="$(cat -)"

  # Because all of the args are key+value - an odd number means we have omitted
  # one. Add '--color' as the implicit key in this case.
  #
  # This is a poor man's positional argument.
  if (( $# % 2 != 0 )); then
    set -- --color "$@"
  fi

  # Parse args
  while (( $# > 0 )); do
    local color padding=""
    case "${1:?}" in
      --color) color="${2:?}"; shift 2 ;;
      --padding) padding="${2:?}"; shift 2 ;;
      *) log::err "Unknown argument to ${funcstack[1]} | arg='$1'"; return 1 ;;
    esac
  done

  # Validate args
  if  [ -z "${color}" ]; then
    log::err "No color specified | funcstack='${funcstack[*]}'"
    return 1
  fi

  # Do work:
  printf "\e[48;5;%sm\e[38;5;%sm" "${color}" "$(color::contrast "${color}")"
  printf "%s%s%s" "${padding}" "${content}" "${padding}"
  printf "\e[0m"
}


# Show off the possible colors
function color::xterm() {
  local fmt_str
  case "${1:-d}" in
    d) fmt_str="%03d" ;;
    x) fmt_str="%02x" ;;
    *) log::err "Unknown format | format='${1:-}'"; return 1 ;;
  esac

  for i in {0..255}; do
    printf "${fmt_str}" "$i" | color::ize "$i" --padding " "
    color::xterm::movement "${i}"
  done
}

function color::xterm::movement() {
  local i=$(( $1 + 1 ))
  if (( i < 16 ));  then
    if ! (( i % 8 )); then
      echo
    fi
  elif (( i < 232 )); then
    if ! (( (i-16) % 6 )); then
      echo
    fi
  elif (( i >= 232 )); then
    if ! (( (i-232) % 12 )); then
      echo
    fi
  else
    log::err "Unknown color | i='${i}'"
    exit 1
  fi

  case "${i}" in
    16|232) echo ;;
  esac
}
