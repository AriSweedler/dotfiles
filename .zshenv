# Helper function
function b-echo() {
  if [ $# -gt 1 ]; then
    echo "Error: give 1 arg only. Maybe try this instead:"
    echo "\tb-echo \"$@\""
    return 1
  fi

  width=120
  chars=$(echo "$1" | wc -c)
  half=$(( ($width - $chars) / 2 ))
  for (( i=0 ; i<$half ; i++ )); do
    printf "#"
  done
  printf " %s " "$1"
  for (( i=0 ; i<$half ; i++ )); do
    printf "#"
  done
  echo
}

