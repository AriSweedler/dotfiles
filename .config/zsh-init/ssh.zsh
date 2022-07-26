function ssh-conf() {
  local -r base="$HOME/.ssh/conf.d"
  # shellcheck disable=SC2012
  local -r file="$(ls -1 "$base" | fzf)"
  vim "$base/$file"
}

# Invoke ssh on any machine in my config.
#
# Example:
#
#     shsh -- ls
#
# This will run fzf to select a machine & then 'ssh <machine> ls' on it
function shsh() {
  # Parse args.
  # Everything before '--' is a --query to fzf.
  # Everything after is the command to run.
  local query="" arg
  while arg="$1" && shift 1 &>/dev/null; do
    [[ "$arg" == "--" ]] && break
    query="$query$arg "
  done

  # If there's no command, do not allow multiple machines to be selected
  local multi
  if (( $# == 0 )); then
    multi="--no-multi"
  else
    multi="--multi"
  fi

  # Invoke fzf to select a
  local -r sshable_machines="$(awk '/Host / {print $2}' "$HOME/.ssh/conf.d/"*)"
  local -r selected=( $(echo "$sshable_machines" | fzf "$multi" --query "$query") )
  log::info "You selected: '${selected[*]}'"

  # If there's no command, simply SSH into the machine and return
  if (( $# == 0 )); then
    ssh "$selected"
    return
  fi

  # Invoke the command on each machine
  for machine in "${selected[@]}"; do
    log::info "On machine '$machine', running command '$*'"
    ssh "$machine" /bin/bash <<< "$@"
    echo
  done
}

# Show the machine dashboard
function machines() {
  b_echo "~~~"
  pushd "$HOME/workspace/hawkeye-tools/output" || exit
  b_echo "Vagrant folders"
  ls -1
  b_echo "machines"
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
  popd &>/dev/null || exit
  b_echo "~~~"
}

function key() {
  log::info "pubkey copied to clipboard"
  pbcopy < "$HOME/.ssh/id_rsa.pub"
}

