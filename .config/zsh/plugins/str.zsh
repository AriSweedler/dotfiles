function str::join() {
  local sep=$1; shift

  # No items: read them from stdin when it is piped. Items given win, so a script whose stdin is
  # not a terminal (a pipe, launchd) still joins its arguments.
  if (( $# == 0 )) && [[ ! -t 0 ]]; then
    local -a lines
    local line
    while IFS= read -r line; do
      lines+=("$line")
    done
    set -- "${lines[@]}"
  fi

  (( $# == 0 )) && return
  # The separator is data, never a printf format: a '%' in it is printed as is.
  printf '%s' "$1"; shift
  local item
  for item in "$@"; do printf '%s%s' "${sep}" "${item}"; done
}

function str::colorize() {
  local color=$1
  local color_var="c_${color}"
  local color_code=${(P)color_var}
  local line
  shift
  # No lines given: color stdin's lines when it is piped. Lines given win, as in str::join.
  if (( $# == 0 )) && [[ ! -t 0 ]]; then
    while IFS= read -r line; do
      printf "%s%s%s\n" "$color_code" "$line" "$c_rst"
    done
  else
    for line in "$@"; do
      printf "%s%s%s\n" "$color_code" "$line" "$c_rst"
    done
  fi
}
