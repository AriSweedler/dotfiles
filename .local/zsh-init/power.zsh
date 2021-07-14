# Functions that give me a bit more power
function double_cd() {
  if [ -z "$2" ]; then
    cd $1
  else
    cd "$1"/*"$2"* || cd "$1"
    b-echo "$(pwd)"
    ls
  fi
}


# Helper function for printing with borders 1
function b-echo() {
  # Handle arguments
  text="${1:-~~~}"
  marker="${2:-=}"
  width="${3:-80}"

  # Validate input
  if [ $# -gt 3 ]; then
    echo "Error: give up to 3 args only. Maybe try this instead:"
    echo "\tb-echo \"$text\" \"$marker\" \"$width\""
    return 1
  fi

  # Center text in divider
  let "half = ($width - ${#text}) / 2"
  for i in $(seq $half); do printf "$marker"; done
  printf " %s " "$text"
  for i in $(seq $half); do printf "$marker"; done

  # Print the newline to finish divider
  echo
}

# Helper function for printing with borders 2
function bb-echo() {
    printf ".\n."
    b-echo "$@" ' '
    echo "."
}

# Show the machine dashboard
function machines() {
  b-echo "~~~"
  pushd "$HOME/workspace/hawkeye-tools/output"
  b-echo "Vagrant folders"
  ls -1
  b-echo "machines"
  # When we get to the 'Host' start looking for the Hostname
  awk '
    prev_filename != FILENAME {
      prev_filename = FILENAME
      if (first == "no") {
        print ""
      } else {
        first = "no"
      }
      print "\t " FILENAME
    }
    /Host / {host=$2}
    /Hostname / {hostname=$2}
    host && hostname {
      print host " - " hostname
      host=""
      hostname=""
    }
  ' "$HOME/.ssh/conf.d/"*
  popd &>/dev/null
  b-echo "~~~"
}

# Easier viewing of json files
alias jvim='vim -c "%!python3 -m json.tool" -c "set ft=json" -c "set foldmethod=syntax"'

# Start a webserver no matter the version of python. Used to be an alias:
# alias www='python -m SimpleHTTPServer 8000'
# But I want it to work for any version of python installed
function www() {
  PORT="8000"
  if [ -z "$1" ]; then
    PORT="$1"
  fi

  PYTHON="python"
  MODULE="http.server"
  if [ $(which python3) ]; then
    PYTHON="python3"
  elif [["$(python --version)" == "Python 2.*" ]]; then
    # Everything else, which should be version 2
    MODULE="SimpleHTTPServer"
  fi

  # Invoke the command
  COMMAND="$PYTHON -m $MODULE $PORT"
  $COMMAND
}

