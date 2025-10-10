function str::join() {
  local sep=$1; shift
  
  # If stdin is piped (not a terminal), read from it
  if [[ ! -t 0 ]]; then
    local -a lines
    while IFS= read -r line; do
      lines+=("$line")
    done
    set -- "${lines[@]}"
  fi
  
  (( $# == 0 )) && return
  printf %s "$1"; shift
  printf "${sep}%s" "$@"
}

function str::colorize() {
  local color=$1
  local color_var="c_${color}"
  local color_code=${(P)color_var}
  
  # If stdin is piped (not a terminal), read from it
  if [[ ! -t 0 ]]; then
    while IFS= read -r line; do
      printf "%s%s%s\n" "$color_code" "$line" "$c_rst"
    done
  else
    shift
    for line in "$@"; do
      printf "%s%s%s\n" "$color_code" "$line" "$c_rst"
    done
  fi
}
