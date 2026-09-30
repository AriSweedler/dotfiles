# Sets REPLY to the ANSI index (15 white or 0 black) that reads best on top of
# the given 256-color index. REPLY instead of stdout so hot loops need no fork.
function color::contrast() {
  local color="$1"

  # In the first 16 - use white for '00' only
  if (( color < 16 )); then
    REPLY=$(( color == 0 ? 15 : 0 ))
    return
  fi

  # In the greyscale (last 24) - use white for the first half
  if (( color > 231 )); then # Greyscale ramp
    REPLY=$(( color < 244 ? 15 : 0 ))
    return
  fi

  # For each block of 36 colors - Use white for the first 3rd
  local row=$(( ( (color-16) % 36) / 6 ))
  REPLY=$(( row < 2 ? 15 : 0 ))
}

function color::ize() {
  # Read all of stdin with the builtin (no fork); drop the trailing newline a
  # piped echo leaves, as $(cat) used to.
  local content
  IFS= read -r -d '' content
  content="${content%$'\n'}"

  # Because all of the args are key+value - an odd number means we have omitted
  # one. Add '--color' as the implicit key in this case.
  #
  # This is a poor man's positional argument.
  if (( $# % 2 != 0 )); then
    set -- --color "$@"
  fi

  # Parse args
  local color
  local padding=""
  while (( $# > 0 )); do
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
  color::contrast "${color}"
  printf "\e[48;5;%sm\e[38;5;%sm" "${color}" "${REPLY}"
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

  # Same cell color::ize would print, built inline: 256 pipes cost ~4s.
  local i
  for i in {0..255}; do
    color::contrast "${i}"
    printf "\e[48;5;%dm\e[38;5;%dm ${fmt_str} \e[0m" "$i" "$REPLY" "$i"
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

  # Dividers between sections
  case "${i}" in
    16|232) echo ;;
  esac
}
