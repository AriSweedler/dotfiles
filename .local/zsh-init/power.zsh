# Functions that give me a bit more power
c_red='\e[31m' ; c_green='\e[32m' ; c_rst='\e[0m'
ven_timestamp() { date "+%Y-%m-%dT%T.000Z" ; }
log_err() { echo -e "${c_red}$(ven_timestamp) ERROR::${c_rst}" "$@" >&2 ; }
log_info() { echo -e "${c_green}$(ven_timestamp) INFO::${c_rst}" "$@" >&2 ; }
run_cmd() { log_info "$@"; "$@" && return; rc=$?; log_err "cmd '$@' failed"; return $?; }

function double_cd() {
  if [ -z "$2" ]; then
    cd "$1"
    return
  fi

  cd "$1"/*"$2"* || cd "$1"
  b-echo "$(pwd)"
  ls
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
    /Host[nN]ame / {hostname=$2}
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

function key() {
  echo "pubkey copied to clipboard"
  pbcopy < "$HOME/.ssh/id_rsa.pub"
}

function scoop() {
  local -r download_dir="$HOME/Downloads"
  echo "Moving all files from '$download_dir' to pwd"
  local -r d="downloads"
  mkdir -p "$d"
  mv "$download_dir"/* "$d"
  printf "\n$d:\n"
  ls "$d"
}
