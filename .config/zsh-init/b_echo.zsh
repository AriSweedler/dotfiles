# Helper function for printing with borders 1
function b_echo() {
  # Handle arguments
  text="${1:-~~~}"
  marker="${2:-=}"
  width="${3:-80}"

  # Validate input
  if [ $# -gt 3 ]; then
    echo "Error: give up to 3 args only. Maybe try this instead:"
    printf "\t${FUNCNAME[0]} '%s' '%s' '%s'" "$text" "$marker" "$width"
    return 1
  fi

  # Center text in divider
  half=$(( (width - ${#text}) / 2 ))
  for _ in $(seq $half); do printf "%s" "$marker"; done
  printf " %s " "$text"
  for _ in $(seq $half); do printf "%s" "$marker"; done

  # Print the newline to finish divider
  echo
}

# Helper function for printing with borders 2
function bb_echo() {
    printf ".\n."
    b_echo "$@" ' '
    echo "."
}

